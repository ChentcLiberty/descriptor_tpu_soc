`timescale 1ns/1ps
`default_nettype none

// TinyTPU AXI-Lite Frontend (step mode + IMEM + sequencer)
//
// Register Map (AXI-Lite 32-bit, byte addresses):
//   0x00  CTRL       bit0=step   write-1 dispatches INSTR_W0 for one cycle
//                   bit1=start  write-1 starts auto-run from imem[0..imem_len-1]
//   0x04  STATUS     bit0=busy   (set by step/start, cleared when VPU drains or seq done)
//                   bit1=running (sequencer is active)
//   0x10  INSTR_W0   32-bit opcode instruction (step mode staging)
//   0x20  UB_DATA    bits[15:0] = 16-bit word to write into UB
//   0x24  UB_PUSH    write-1 drives ub_wr_host_valid for one cycle
//   0x30  IMEM_ADDR  instruction slot address (0..IMEM_DEPTH-1)
//   0x34  IMEM_W0    32-bit opcode instruction to commit
//   0x40  IMEM_WE    write-1 commits IMEM_W0 into imem[IMEM_ADDR]
//   0x44  IMEM_LEN   number of valid instructions in IMEM
//   0x50  LEAK       leaky-relu factor (Q8.8)
//   0x54  INV_BATCH  inverse batch scaling for loss path (Q8.8)
//   0x58  LR         learning rate for in-UB gradient descent (Q8.8)
//
// Instruction format (32-bit opcode):
//   opcode=3'b000  NOP
//   opcode=3'b001  SWITCH  (sys_switch)
//   opcode=3'b010  UB_RD   [8:3]=addr[5:0] [12:9]=row[3:0] [14:13]=col[1:0]
//                          [15]=transpose [18:16]=ptr_sel [22:19]=vpu_pathway
//   opcode=3'b011  UB_WR_HOST  [18:3]=data[15:0]

module tpu_frontend_axil #(
    parameter int SYSTOLIC_ARRAY_WIDTH = 2,
    parameter int IMEM_DEPTH           = 64
)(
    // AXI-Lite slave
    input  logic        s_axil_aclk,
    input  logic        s_axil_aresetn,   // active-low

    input  logic [11:0] s_axil_awaddr,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,

    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,

    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,

    input  logic [11:0] s_axil_araddr,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,

    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,

    // TPU done input (vpu_valid_out drained)
    input  logic        tpu_vpu_valid_in,  // OR of all vpu_valid_out

    // Clock / reset to TPU core
    output logic        clk_out,
    output logic        rst_out,           // active-high to TPU

    // UB host write (direct AXI path, to tpu.sv ub_wr_host_*)
    output logic [15:0] ub_wr_host_data_out_0,
    output logic        ub_wr_host_valid_out_0,
    output logic [15:0] ub_wr_host_data_out_1,
    output logic        ub_wr_host_valid_out_1,
    output logic        ub_wr_ptr_restore_out,

    // Decoded TPU control signals (from control_unit, to tpu.sv inputs)
    output logic        sys_switch_out,
    output logic        ub_rd_start_out,
    output logic        ub_rd_transpose_out,
    output logic [1:0]  ub_rd_col_size_out,
    output logic [3:0]  ub_rd_row_size_out,
    output logic [5:0]  ub_rd_addr_out,
    output logic [2:0]  ub_ptr_sel_out,
    output logic [3:0]  vpu_data_pathway_out,
    output logic [15:0] inv_batch_size_times_two_out,
    output logic [15:0] vpu_leak_factor_out,
    output logic [15:0] learning_rate_out
);

    assign clk_out = s_axil_aclk;
    assign rst_out = ~s_axil_aresetn;
    assign ub_wr_ptr_restore_out = start_pulse;

    // -------------------------------------------------------------------------
    // Staged instruction registers and pulse signals
    // -------------------------------------------------------------------------
    logic [31:0] instr_w0_reg;
    logic [15:0] ub_data0_reg;  // lane0 data
    logic [15:0] ub_data1_reg;  // lane1 data
    logic        step_pulse;
    logic        start_pulse;
    logic        ub_push0_pulse; // one cycle: push lane0
    logic        ub_push1_pulse; // one cycle: push lane1
    logic        busy_reg;
    logic [15:0] leak_factor_reg;
    logic [15:0] inv_batch_n2_reg;
    logic [15:0] learning_rate_reg;
    logic [3:0]  vpu_pathway_reg;  // latched vpu_data_pathway, persists between instructions

    // -------------------------------------------------------------------------
    // IMEM declarations (used by sequencer below)
    // -------------------------------------------------------------------------
    logic [31:0] imem [0:IMEM_DEPTH-1];
    logic [$clog2(IMEM_DEPTH)-1:0] imem_addr_reg;
    logic [31:0] imem_w0_reg;
    logic [5:0]  imem_len_reg;

    // -------------------------------------------------------------------------
    // Sequencer state machine
    // SEQ_IDLE    : waiting for start or step
    // SEQ_DISPATCH: pulse instr to control_unit for one cycle
    // SEQ_WAIT    : waiting for vpu_valid to drain (ptr_sel needs it)
    // SEQ_ADVANCE : advance PC, go to next instruction or done
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        SEQ_IDLE     = 2'b00,
        SEQ_DISPATCH = 2'b01,
        SEQ_WAIT     = 2'b10,
        SEQ_ADVANCE  = 2'b11
    } seq_state_t;
    seq_state_t seq_state;

    logic [$clog2(IMEM_DEPTH)-1:0] pc;
    logic        seq_running;         // sequencer is active
    logic        seq_instr_pulse;     // one cycle: drive imem[pc] to CU
    logic [31:0] seq_instr;           // current instruction
    logic        vpu_valid_prev;
    logic        vpu_drain;           // vpu_valid fell this cycle

    // needs_wait: bit[23] in instruction = explicit wait-after flag
    logic seq_needs_wait;
    assign seq_needs_wait = seq_instr[23];

    always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
        if (!s_axil_aresetn) begin
            seq_state       <= SEQ_IDLE;
            pc              <= '0;
            seq_running     <= 1'b0;
            seq_instr_pulse <= 1'b0;
            seq_instr       <= '0;
            vpu_valid_prev  <= 1'b0;
            vpu_drain       <= 1'b0;
            busy_reg        <= 1'b0;
        end else begin
            vpu_valid_prev <= tpu_vpu_valid_in;
            vpu_drain      <= vpu_valid_prev && !tpu_vpu_valid_in;
            seq_instr_pulse <= 1'b0;
            // Latch vpu_pathway on every UB_RD dispatch so it persists
            if (seq_instr_pulse && seq_instr[2:0] == 3'b010)
                vpu_pathway_reg <= seq_instr[22:19];

            case (seq_state)
                SEQ_IDLE: begin
                    seq_running <= 1'b0;
                    if (step_pulse) begin
                        seq_instr       <= instr_w0_reg;
                        seq_instr_pulse <= 1'b1;
                        busy_reg        <= 1'b1;
                        seq_state       <= SEQ_WAIT;
                    end else if (start_pulse) begin
                        pc          <= '0;
                        seq_instr   <= imem[0];
                        seq_running <= 1'b1;
                        busy_reg    <= 1'b1;
                        seq_state   <= SEQ_DISPATCH;
                    end
                end

                SEQ_DISPATCH: begin
                    seq_instr_pulse <= 1'b1;
                    if (seq_needs_wait)
                        seq_state <= SEQ_WAIT;
                    else
                        seq_state <= SEQ_ADVANCE;
                end

                SEQ_WAIT: begin
                    if (vpu_drain) begin
                        if (seq_running)
                            seq_state <= SEQ_ADVANCE;
                        else begin
                            busy_reg  <= 1'b0;
                            seq_state <= SEQ_IDLE;
                        end
                    end
                end

                SEQ_ADVANCE: begin
                    if (pc + 1 < {{($clog2(IMEM_DEPTH)-6){1'b0}}, imem_len_reg}) begin
                        pc        <= pc + 1;
                        seq_instr <= imem[pc + 1];
                        seq_state <= SEQ_DISPATCH;
                    end else begin
                        seq_running <= 1'b0;
                        busy_reg    <= 1'b0;
                        seq_state   <= SEQ_IDLE;
                    end
                end

                default: seq_state <= SEQ_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // AXI-Lite write channel
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        W_IDLE      = 2'b00,
        W_WAIT_W    = 2'b01,
        W_WAIT_AW   = 2'b10,
        W_RESP      = 2'b11
    } w_state_t;
    w_state_t w_state;

    logic [11:0] aw_lat;
    logic [31:0] wd_lat;
    logic        wr_fire;

    assign s_axil_awready = (w_state == W_IDLE) || (w_state == W_WAIT_AW);
    assign s_axil_wready  = (w_state == W_IDLE) || (w_state == W_WAIT_W);

    always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
        if (!s_axil_aresetn) begin
            w_state       <= W_IDLE;
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
            aw_lat  <= '0;
            wd_lat  <= '0;
            wr_fire <= 1'b0;
        end else begin
            wr_fire <= 1'b0;
            case (w_state)
                W_IDLE: begin
                    s_axil_bvalid <= 1'b0;
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        aw_lat  <= s_axil_awaddr;
                        wd_lat  <= s_axil_wdata;
                        wr_fire <= 1'b1;
                        w_state <= W_RESP;
                    end else if (s_axil_awvalid) begin
                        aw_lat  <= s_axil_awaddr;
                        w_state <= W_WAIT_W;
                    end else if (s_axil_wvalid) begin
                        wd_lat  <= s_axil_wdata;
                        w_state <= W_WAIT_AW;
                    end
                end
                W_WAIT_W: begin
                    if (s_axil_wvalid) begin
                        wd_lat  <= s_axil_wdata;
                        wr_fire <= 1'b1;
                        w_state <= W_RESP;
                    end
                end
                W_WAIT_AW: begin
                    if (s_axil_awvalid) begin
                        aw_lat  <= s_axil_awaddr;
                        wr_fire <= 1'b1;
                        w_state <= W_RESP;
                    end
                end
                W_RESP: begin
                    s_axil_bvalid <= 1'b1;
                    s_axil_bresp  <= 2'b00;
                    if (s_axil_bvalid && s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        w_state       <= W_IDLE;
                    end
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Register write decode
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
        if (!s_axil_aresetn) begin
            instr_w0_reg     <= '0;
            ub_data0_reg     <= '0;
            ub_data1_reg     <= '0;
            step_pulse       <= 1'b0;
            start_pulse      <= 1'b0;
            ub_push0_pulse   <= 1'b0;
            ub_push1_pulse   <= 1'b0;
            imem_addr_reg    <= '0;
            imem_w0_reg      <= '0;
            imem_len_reg     <= '0;
            leak_factor_reg  <= '0;
            inv_batch_n2_reg <= '0;
            learning_rate_reg <= '0;
            vpu_pathway_reg  <= '0;
            for (int i = 0; i < IMEM_DEPTH; i++) imem[i] <= '0;
        end else begin
            step_pulse     <= 1'b0;
            start_pulse    <= 1'b0;
            ub_push0_pulse <= 1'b0;
            ub_push1_pulse <= 1'b0;
            if (wr_fire) begin
                case (aw_lat)
                    12'h000: begin
                        if (wd_lat[0]) step_pulse  <= 1'b1;
                        if (wd_lat[1]) start_pulse <= 1'b1;
                    end
                    12'h010: instr_w0_reg    <= wd_lat;
                    12'h020: ub_data0_reg    <= wd_lat[15:0];  // lane0 data
                    12'h024: begin                              // UB_PUSH: bit0=lane0, bit1=lane1
                        if (wd_lat[0]) ub_push0_pulse <= 1'b1;
                        if (wd_lat[1]) ub_push1_pulse <= 1'b1;
                    end
                    12'h028: ub_data1_reg    <= wd_lat[15:0];  // lane1 data
                    12'h030: imem_addr_reg   <= wd_lat[$clog2(IMEM_DEPTH)-1:0];
                    12'h034: imem_w0_reg     <= wd_lat;
                    12'h040: if (wd_lat[0]) imem[imem_addr_reg] <= imem_w0_reg;
                    12'h044: imem_len_reg    <= wd_lat[5:0];
                    12'h050: leak_factor_reg   <= wd_lat[15:0];
                    12'h054: inv_batch_n2_reg  <= wd_lat[15:0];
                    12'h058: learning_rate_reg <= wd_lat[15:0];
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI-Lite read channel
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axil_aclk or negedge s_axil_aresetn) begin
        if (!s_axil_aresetn) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= 2'b00;
        end else begin
            s_axil_arready <= 1'b0;
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= 2'b00;
                case (s_axil_araddr)
                    12'h000: s_axil_rdata <= 32'h0;
                    12'h004: s_axil_rdata <= {30'h0, seq_running, busy_reg};
                    12'h010: s_axil_rdata <= instr_w0_reg;
                    12'h020: s_axil_rdata <= {16'h0, ub_data0_reg};
                    12'h030: s_axil_rdata <= {26'h0, imem_addr_reg};
                    12'h034: s_axil_rdata <= imem_w0_reg;
                    12'h044: s_axil_rdata <= {26'h0, imem_len_reg};
                    12'h050: s_axil_rdata <= {16'h0, leak_factor_reg};
                    12'h054: s_axil_rdata <= {16'h0, inv_batch_n2_reg};
                    12'h058: s_axil_rdata <= {16'h0, learning_rate_reg};
                    default:  s_axil_rdata <= 32'hDEAD_BEEF;
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // control_unit: driven by sequencer
    // -------------------------------------------------------------------------
    logic [31:0] instr_to_cu;
    assign instr_to_cu = seq_instr_pulse ? seq_instr : '0;

    // cu outputs for ub host write path (UB_WR_HOST opcode)
    logic [15:0] cu_ub_data_0, cu_ub_data_1;
    logic        cu_ub_valid_0, cu_ub_valid_1;
    logic [3:0]  cu_vpu_data_pathway;  // unused directly; pathway persists via vpu_pathway_reg

    control_unit cu_inst (
        .instruction                 (instr_to_cu),
        .sys_switch_in               (sys_switch_out),
        .ub_rd_start_in              (ub_rd_start_out),
        .ub_rd_transpose             (ub_rd_transpose_out),
        .ub_wr_host_valid_in_1       (cu_ub_valid_0),
        .ub_wr_host_valid_in_2       (cu_ub_valid_1),
        .ub_rd_col_size              (ub_rd_col_size_out),
        .ub_rd_row_size              (ub_rd_row_size_out),
        .ub_rd_addr_in               (ub_rd_addr_out),
        .ub_ptr_sel                  (ub_ptr_sel_out),
        .ub_wr_host_data_in_1        (cu_ub_data_0),
        .ub_wr_host_data_in_2        (cu_ub_data_1),
        .vpu_data_pathway            (cu_vpu_data_pathway),
        .inv_batch_size_times_two_in (inv_batch_n2_reg),
        .vpu_leak_factor_in          (leak_factor_reg)
    );

    // -------------------------------------------------------------------------
    // UB host write mux: AXI UB_PUSH (per-lane) takes priority over CU UB_WR_HOST
    // -------------------------------------------------------------------------
    assign inv_batch_size_times_two_out = inv_batch_n2_reg;
    assign vpu_leak_factor_out          = leak_factor_reg;
    assign learning_rate_out            = learning_rate_reg;
    assign vpu_data_pathway_out         = vpu_pathway_reg;

    assign ub_wr_host_valid_out_0 = ub_push0_pulse ? 1'b1        : cu_ub_valid_0;
    assign ub_wr_host_valid_out_1 = ub_push1_pulse ? 1'b1        : cu_ub_valid_1;
    assign ub_wr_host_data_out_0  = ub_push0_pulse ? ub_data0_reg : cu_ub_data_0;
    assign ub_wr_host_data_out_1  = ub_push1_pulse ? ub_data1_reg : cu_ub_data_1;

endmodule