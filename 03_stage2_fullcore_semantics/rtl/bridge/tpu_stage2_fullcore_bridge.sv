`timescale 1ns / 1ps
`default_nettype none

import tinytpu_frontend_pkg::*;

module tpu_stage2_fullcore_bridge #(
    parameter [2:0] AXI_SIZE_WORD = 3'b010
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        launch_pulse,
    input  wire        soft_reset_pulse,
    input  wire [31:0] desc_base_addr,

    input  wire [15:0] vpu_data_out_1,
    input  wire [15:0] vpu_data_out_2,
    input  wire        vpu_valid_out_1,
    input  wire        vpu_valid_out_2,
    input  wire [15:0] ub_rd_y_data_out_0,
    input  wire [15:0] ub_rd_y_data_out_1,
    input  wire        ub_rd_y_valid_out_0,
    input  wire        ub_rd_y_valid_out_1,

    output reg         core_reset_req,

    output reg         status_busy,
    output reg         status_done,
    output reg         status_error,

    output reg  [31:0] desc_net_id_reg,
    output reg  [31:0] desc_input_addr_reg,
    output reg  [31:0] desc_output_addr_reg,
    output reg  [31:0] desc_param_addr_reg,
    output reg  [31:0] desc_scratch_addr_reg,
    output reg  [31:0] desc_input_words_reg,
    output reg  [31:0] desc_output_words_reg,
    output reg  [31:0] desc_flags_reg,

    output reg  [31:0] input_fetch_word_count_reg,
    output reg  [31:0] input_checksum_reg,
    output reg  [31:0] input_last_word_reg,
    output reg  [31:0] param_fetch_word_count_reg,
    output reg  [31:0] param_checksum_reg,
    output reg  [31:0] param_last_word_reg,

    output reg  [31:0] m_axi_araddr,
    output wire [1:0]  m_axi_arburst,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [3:0]  m_axi_arcache,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    output reg  [31:0] m_axi_awaddr,
    output wire [1:0]  m_axi_awburst,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [3:0]  m_axi_awcache,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    output reg         fe_cmd_valid,
    output reg         fe_cmd_write,
    output reg  [11:0] fe_cmd_addr,
    output reg  [31:0] fe_cmd_wdata,
    input  wire        fe_cmd_ready,
    input  wire        fe_rsp_valid,
    input  wire [31:0] fe_rsp_rdata,
    output reg         fe_rsp_ready,

    output reg         tile_exec_valid,
    output wire [5:0]  tile_exec_input_addr,
    output wire [5:0]  tile_exec_weight_addr,
    output wire [5:0]  tile_exec_bias_addr,
    output wire [5:0]  tile_exec_y_addr,
    output wire [3:0]  tile_exec_pathway,
    input  wire        tile_exec_ready,
    input  wire        tile_exec_done,
    output reg         readback_exec_valid,
    output wire [5:0]  readback_exec_addr,
    input  wire        readback_exec_ready
);

    localparam integer MAX_INPUT_WORDS = 256;
    localparam integer TPU_DESC_F_RELU_BIT            = 0;
    localparam integer TPU_DESC_F_TILE2X2_Q8_8_BIT    = 16;
    localparam integer TPU_DESC_F_SCRATCH_LEAK_BIT    = 24;
    localparam integer TPU_DESC_F_TRANSITION_MSE_BIT  = 25;

    localparam [6:0]
        ST_IDLE              = 7'd0,
        ST_DESC_AR           = 7'd1,
        ST_DESC_R            = 7'd2,
        ST_VALIDATE          = 7'd3,
        ST_INPUT_AR          = 7'd4,
        ST_INPUT_R           = 7'd5,
        ST_AUX_AR            = 7'd62,
        ST_AUX_R             = 7'd63,
        ST_PREP_OUTPUT       = 7'd6,
        ST_CORE_RESET        = 7'd7,
        ST_PARAM_AR          = 7'd8,
        ST_PARAM_R           = 7'd9,
        ST_FE_CFG_LEAK       = 7'd10,
        ST_FE_CFG_INV_BATCH  = 7'd11,
        ST_FE_CFG_LR         = 7'd12,
        ST_FE_LOAD_X0        = 7'd13,
        ST_FE_PUSH_X0        = 7'd14,
        ST_FE_LOAD_X1        = 7'd15,
        ST_FE_PUSH_X1        = 7'd16,
        ST_FE_LOAD_W00       = 7'd17,
        ST_FE_LOAD_W01       = 7'd18,
        ST_FE_PUSH_W0        = 7'd19,
        ST_FE_LOAD_W10       = 7'd20,
        ST_FE_LOAD_W11       = 7'd21,
        ST_FE_PUSH_W1        = 7'd22,
        ST_FE_LOAD_B0        = 7'd23,
        ST_FE_LOAD_B1        = 7'd24,
        ST_FE_PUSH_B         = 7'd25,
        ST_FE_START          = 7'd54,
        ST_FE_STATUS_WAIT    = 7'd56,
        ST_AXI_WB_AW         = 7'd57,
        ST_AXI_WB_W          = 7'd58,
        ST_AXI_WB_B          = 7'd59,
        ST_DONE              = 7'd60,
        ST_FAIL              = 7'd61,
        ST_FE_RB_LOAD        = 7'd64,
        ST_FE_RB_WAIT        = 7'd66,
        ST_Y_AR              = 7'd67,
        ST_Y_R               = 7'd68,
        ST_FE_LOAD_Y0        = 7'd69,
        ST_FE_LOAD_Y1        = 7'd70,
        ST_FE_PUSH_Y         = 7'd71;

    reg [6:0]  state_reg;
    reg [31:0] desc_base_reg;
    reg [3:0]  desc_word_idx_reg;
    reg [1:0]  param_word_idx_reg;
    reg [31:0] input_fetch_idx_reg;
    reg [31:0] output_word_idx_reg;
    reg [31:0] tile_word_idx_reg;

    reg [31:0] input_mem [0:MAX_INPUT_WORDS-1];
    reg [31:0] param_word0_reg;
    reg [31:0] param_word1_reg;
    reg [31:0] param_word2_reg;

    reg [31:0] fe_write_data_reg;
    reg [11:0] fe_write_addr_reg;
    reg        fe_cmd_active_reg;
    reg        fe_cmd_is_write_reg;
    reg        fe_read_wait_reg;
    reg        fe_write_done_reg;

    reg [11:0] fe_read_addr_reg;
    reg        fe_read_done_reg;
    reg [31:0] fe_read_data_reg;

    reg [15:0] captured_out0_reg;
    reg [15:0] captured_out1_reg;
    reg        captured_out0_seen_reg;
    reg        captured_out1_seen_reg;
    reg [15:0] ub_readback_out0_reg;
    reg [15:0] ub_readback_out1_reg;
    reg        ub_readback_out0_seen_reg;
    reg        ub_readback_out1_seen_reg;
    reg [15:0] desc_leak_factor_reg;
    reg [31:0] aux_y_word_reg;

    wire relu_enable;
    wire tile2x2_enable;
    wire scratch_leak_enable;
    wire transition_mse_enable;
    wire [3:0] terminal_tile_pathway;
    wire [3:0] current_tile_pathway;
    wire [15:0] current_inv_batch_factor;
    wire [31:0] final_output_word;
    wire [31:0] param_stride_words;
    wire [31:0] current_param_base_addr;
    wire [31:0] current_tile_param_word0_addr;
    wire [31:0] current_tile_param_word1_addr;
    wire [31:0] current_output_bias_param_addr;
    wire [31:0] current_input_word;
    wire [31:0] current_tile_input_ub_addr;
    wire [31:0] current_tile_weight_ub_addr;
    wire [31:0] current_tile_bias_ub_addr;
    wire [31:0] current_tile_y_ub_addr;
    wire [31:0] current_output_result_ub_addr;
    wire [31:0] current_bias_word;

    assign relu_enable            = desc_flags_reg[TPU_DESC_F_RELU_BIT];
    assign tile2x2_enable         = desc_flags_reg[TPU_DESC_F_TILE2X2_Q8_8_BIT];
    assign scratch_leak_enable    = desc_flags_reg[TPU_DESC_F_SCRATCH_LEAK_BIT];
    assign transition_mse_enable  = desc_flags_reg[TPU_DESC_F_TRANSITION_MSE_BIT];
    assign terminal_tile_pathway  = transition_mse_enable ? 4'b1111 : (relu_enable ? 4'b1100 : 4'b1000);
    assign current_tile_pathway   = ((tile_word_idx_reg + 32'd1) >= desc_input_words_reg) ? terminal_tile_pathway : 4'b1000;
    assign current_inv_batch_factor = transition_mse_enable ? 16'h0100 : 16'd0;
    assign final_output_word      = {ub_readback_out1_reg, ub_readback_out0_reg};
    assign param_stride_words     = (desc_input_words_reg << 1) + 32'd1;
    assign current_param_base_addr= desc_param_addr_reg + ((output_word_idx_reg * param_stride_words) << 2);
    assign current_tile_param_word0_addr = current_param_base_addr + (tile_word_idx_reg << 3);
    assign current_tile_param_word1_addr = current_param_base_addr + (tile_word_idx_reg << 3) + 32'd4;
    assign current_output_bias_param_addr = current_param_base_addr + (desc_input_words_reg << 3);
    assign current_input_word = (tile_word_idx_reg < MAX_INPUT_WORDS) ? input_mem[tile_word_idx_reg] : 32'd0;
    assign current_tile_input_ub_addr = 32'd0;
    assign current_tile_weight_ub_addr = 32'd2;
    assign current_tile_bias_ub_addr = 32'd6;
    assign current_tile_y_ub_addr = 32'd8;
    // Forward tiles write back at UB[8:9]. Transition tiles push Y at UB[8:9],
    // so the VPU result lands at UB[10:11] instead.
    assign current_output_result_ub_addr = transition_mse_enable ? 32'd10 : 32'd8;
    assign current_bias_word = (tile_word_idx_reg == 32'd0) ? param_word2_reg : {captured_out1_reg, captured_out0_reg};
    assign tile_exec_input_addr  = current_tile_input_ub_addr[5:0];
    assign tile_exec_weight_addr = current_tile_weight_ub_addr[5:0];
    assign tile_exec_bias_addr   = current_tile_bias_ub_addr[5:0];
    assign tile_exec_y_addr      = current_tile_y_ub_addr[5:0];
    assign tile_exec_pathway     = current_tile_pathway;
    assign readback_exec_addr    = current_output_result_ub_addr[5:0];

    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = AXI_SIZE_WORD;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = AXI_SIZE_WORD;
    assign m_axi_awcache = 4'b0011;


    task clear_desc_regs;
        begin
            desc_net_id_reg       <= 32'd0;
            desc_input_addr_reg   <= 32'd0;
            desc_output_addr_reg  <= 32'd0;
            desc_param_addr_reg   <= 32'd0;
            desc_scratch_addr_reg <= 32'd0;
            desc_input_words_reg  <= 32'd0;
            desc_output_words_reg <= 32'd0;
            desc_flags_reg        <= 32'd0;
        end
    endtask

    task clear_counters;
        begin
            input_fetch_word_count_reg <= 32'd0;
            input_checksum_reg         <= 32'd0;
            input_last_word_reg        <= 32'd0;
            param_fetch_word_count_reg <= 32'd0;
            param_checksum_reg         <= 32'd0;
            param_last_word_reg        <= 32'd0;
        end
    endtask

    task clear_shared_axi_master;
        begin
            m_axi_araddr  <= 32'd0;
            m_axi_arvalid <= 1'b0;
            m_axi_awaddr  <= 32'd0;
            m_axi_bready  <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_wdata   <= 32'd0;
            m_axi_wstrb   <= 4'd0;
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;
        end
    endtask

    task clear_frontend_master;
        begin
            fe_cmd_valid   <= 1'b0;
            fe_cmd_write   <= 1'b0;
            fe_cmd_addr    <= 12'd0;
            fe_cmd_wdata   <= 32'd0;
            fe_rsp_ready   <= 1'b0;
            tile_exec_valid    <= 1'b0;
            readback_exec_valid<= 1'b0;
        end
    endtask

    task start_fe_write;
        input [11:0] addr;
        input [31:0] data;
        begin
            fe_write_addr_reg   <= addr;
            fe_write_data_reg   <= data;
            fe_cmd_active_reg   <= 1'b1;
            fe_cmd_is_write_reg <= 1'b1;
            fe_read_wait_reg    <= 1'b0;
            fe_write_done_reg   <= 1'b0;
        end
    endtask

    task start_fe_read;
        input [11:0] addr;
        begin
            fe_read_addr_reg    <= addr;
            fe_cmd_active_reg   <= 1'b1;
            fe_cmd_is_write_reg <= 1'b0;
            fe_read_wait_reg    <= 1'b0;
            fe_read_done_reg    <= 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_reg                <= ST_IDLE;
            desc_base_reg            <= 32'd0;
            desc_word_idx_reg        <= 4'd0;
            param_word_idx_reg       <= 2'd0;
            input_fetch_idx_reg      <= 32'd0;
            output_word_idx_reg      <= 32'd0;
            tile_word_idx_reg        <= 32'd0;
            core_reset_req           <= 1'b0;
            status_busy              <= 1'b0;
            status_done              <= 1'b0;
            status_error             <= 1'b0;
            param_word0_reg          <= 32'd0;
            param_word1_reg          <= 32'd0;
            param_word2_reg          <= 32'd0;
            fe_write_data_reg        <= 32'd0;
            fe_write_addr_reg        <= 12'd0;
            fe_cmd_active_reg        <= 1'b0;
            fe_cmd_is_write_reg      <= 1'b0;
            fe_read_wait_reg         <= 1'b0;
            fe_write_done_reg        <= 1'b0;
            fe_read_addr_reg         <= 12'd0;
            fe_read_done_reg         <= 1'b0;
            fe_read_data_reg         <= 32'd0;
            captured_out0_reg        <= 16'd0;
            captured_out1_reg        <= 16'd0;
            captured_out0_seen_reg   <= 1'b0;
            captured_out1_seen_reg   <= 1'b0;
            ub_readback_out0_reg     <= 16'd0;
            ub_readback_out1_reg     <= 16'd0;
            ub_readback_out0_seen_reg<= 1'b0;
            ub_readback_out1_seen_reg<= 1'b0;
            desc_leak_factor_reg     <= 16'd0;
            aux_y_word_reg           <= 32'd0;
            clear_desc_regs();
            clear_counters();
            clear_shared_axi_master();
            clear_frontend_master();
            tile_exec_valid         <= 1'b0;
            readback_exec_valid     <= 1'b0;
        end else if(soft_reset_pulse) begin
            state_reg                <= ST_IDLE;
            desc_base_reg            <= 32'd0;
            desc_word_idx_reg        <= 4'd0;
            param_word_idx_reg       <= 2'd0;
            input_fetch_idx_reg      <= 32'd0;
            output_word_idx_reg      <= 32'd0;
            tile_word_idx_reg        <= 32'd0;
            core_reset_req           <= 1'b0;
            status_busy              <= 1'b0;
            status_done              <= 1'b0;
            status_error             <= 1'b0;
            param_word0_reg          <= 32'd0;
            param_word1_reg          <= 32'd0;
            param_word2_reg          <= 32'd0;
            fe_write_data_reg        <= 32'd0;
            fe_write_addr_reg        <= 12'd0;
            fe_cmd_active_reg        <= 1'b0;
            fe_cmd_is_write_reg      <= 1'b0;
            fe_read_wait_reg         <= 1'b0;
            fe_write_done_reg        <= 1'b0;
            fe_read_addr_reg         <= 12'd0;
            fe_read_done_reg         <= 1'b0;
            fe_read_data_reg         <= 32'd0;
            captured_out0_reg        <= 16'd0;
            captured_out1_reg        <= 16'd0;
            captured_out0_seen_reg   <= 1'b0;
            captured_out1_seen_reg   <= 1'b0;
            ub_readback_out0_reg     <= 16'd0;
            ub_readback_out1_reg     <= 16'd0;
            ub_readback_out0_seen_reg<= 1'b0;
            ub_readback_out1_seen_reg<= 1'b0;
            desc_leak_factor_reg     <= 16'd0;
            aux_y_word_reg           <= 32'd0;
            clear_desc_regs();
            clear_counters();
            clear_shared_axi_master();
            clear_frontend_master();
            tile_exec_valid         <= 1'b0;
            readback_exec_valid     <= 1'b0;
        end else begin
            fe_write_done_reg <= 1'b0;
            fe_read_done_reg  <= 1'b0;
            core_reset_req    <= 1'b0;

            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;

            fe_cmd_valid   <= 1'b0;
            fe_cmd_write   <= 1'b0;
            fe_cmd_addr    <= 12'd0;
            fe_cmd_wdata   <= 32'd0;
            fe_rsp_ready   <= 1'b0;
            tile_exec_valid    <= 1'b0;
            readback_exec_valid<= 1'b0;

            if(fe_cmd_active_reg) begin
                fe_cmd_valid <= 1'b1;
                fe_cmd_write <= fe_cmd_is_write_reg;
                fe_cmd_addr  <= fe_cmd_is_write_reg ? fe_write_addr_reg : fe_read_addr_reg;
                fe_cmd_wdata <= fe_write_data_reg;
                if(fe_cmd_ready) begin
                    fe_cmd_active_reg <= 1'b0;
                    if(fe_cmd_is_write_reg) begin
                        fe_write_done_reg <= 1'b1;
                    end else begin
                        fe_read_wait_reg <= 1'b1;
                    end
                end
            end

            if(fe_read_wait_reg) begin
                fe_rsp_ready <= 1'b1;
                if(fe_rsp_valid) begin
                    fe_read_wait_reg <= 1'b0;
                    fe_read_done_reg <= 1'b1;
                    fe_read_data_reg <= fe_rsp_rdata;
                end
            end

            if(status_busy) begin
                if(vpu_valid_out_1 && !captured_out0_seen_reg) begin
                    captured_out0_reg      <= vpu_data_out_1;
                    captured_out0_seen_reg <= 1'b1;
                end
                if(vpu_valid_out_2 && !captured_out1_seen_reg) begin
                    captured_out1_reg      <= vpu_data_out_2;
                    captured_out1_seen_reg <= 1'b1;
                end
            end

            if(ub_rd_y_valid_out_0 && !ub_readback_out0_seen_reg) begin
                ub_readback_out0_reg      <= ub_rd_y_data_out_0;
                ub_readback_out0_seen_reg <= 1'b1;
            end
            if(ub_rd_y_valid_out_1 && !ub_readback_out1_seen_reg) begin
                ub_readback_out1_reg      <= ub_rd_y_data_out_1;
                ub_readback_out1_seen_reg <= 1'b1;
            end

            case(state_reg)
                ST_IDLE: begin
                    status_busy  <= 1'b0;
                    if(launch_pulse) begin
                        status_busy            <= 1'b1;
                        status_done            <= 1'b0;
                        status_error           <= 1'b0;
                        desc_base_reg          <= desc_base_addr;
                        desc_word_idx_reg      <= 4'd0;
                        param_word_idx_reg     <= 2'd0;
                        input_fetch_idx_reg    <= 32'd0;
                        output_word_idx_reg    <= 32'd0;
                        tile_word_idx_reg      <= 32'd0;
                        param_word0_reg        <= 32'd0;
                        param_word1_reg        <= 32'd0;
                        param_word2_reg        <= 32'd0;
                        captured_out0_reg      <= 16'd0;
                        captured_out1_reg      <= 16'd0;
                        captured_out0_seen_reg <= 1'b0;
                        captured_out1_seen_reg <= 1'b0;
                        ub_readback_out0_reg   <= 16'd0;
                        ub_readback_out1_reg   <= 16'd0;
                        ub_readback_out0_seen_reg <= 1'b0;
                        ub_readback_out1_seen_reg <= 1'b0;
                        desc_leak_factor_reg   <= 16'd0;
                        aux_y_word_reg         <= 32'd0;
                        clear_desc_regs();
                        clear_counters();
                        m_axi_araddr      <= desc_base_addr;
                        m_axi_arvalid     <= 1'b1;
                        state_reg         <= ST_DESC_AR;
                    end
                end

                ST_DESC_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_DESC_R;
                    end
                end

                ST_DESC_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        case(desc_word_idx_reg)
                            4'd0: desc_net_id_reg       <= m_axi_rdata;
                            4'd1: desc_input_addr_reg   <= m_axi_rdata;
                            4'd2: desc_output_addr_reg  <= m_axi_rdata;
                            4'd3: desc_param_addr_reg   <= m_axi_rdata;
                            4'd4: desc_scratch_addr_reg <= m_axi_rdata;
                            4'd5: desc_input_words_reg  <= m_axi_rdata;
                            4'd6: desc_output_words_reg <= m_axi_rdata;
                            4'd7: desc_flags_reg        <= m_axi_rdata;
                            default: begin end
                        endcase

                        if(desc_word_idx_reg == 4'd7) begin
                            state_reg <= ST_VALIDATE;
                        end else begin
                            desc_word_idx_reg <= desc_word_idx_reg + 4'd1;
                            m_axi_araddr      <= desc_base_reg + ((desc_word_idx_reg + 4'd1) << 2);
                            m_axi_arvalid     <= 1'b1;
                            state_reg         <= ST_DESC_AR;
                        end
                    end
                end

                ST_VALIDATE: begin
                    // Current coverage includes the original forward packed-linear
                    // subset plus a transition MSE subset on the terminal tile.
                    if(!tile2x2_enable ||
                       (desc_output_words_reg == 32'd0) ||
                       (transition_mse_enable && (!relu_enable || scratch_leak_enable || (desc_scratch_addr_reg == 32'd0)))) begin
                        status_error <= 1'b1;
                        status_busy  <= 1'b0;
                        state_reg    <= ST_FAIL;
                    end else begin
                        input_fetch_idx_reg <= 32'd0;
                        m_axi_araddr        <= desc_input_addr_reg;
                        m_axi_arvalid       <= 1'b1;
                        state_reg           <= ST_INPUT_AR;
                    end
                end

                ST_INPUT_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_INPUT_R;
                    end
                end

                ST_INPUT_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        input_mem[input_fetch_idx_reg] <= m_axi_rdata;
                        input_fetch_word_count_reg <= input_fetch_word_count_reg + 32'd1;
                        input_checksum_reg         <= input_checksum_reg + m_axi_rdata;
                        input_last_word_reg        <= m_axi_rdata;
                        if(input_fetch_idx_reg + 32'd1 >= desc_input_words_reg) begin
                            if(relu_enable && scratch_leak_enable && !transition_mse_enable && (desc_scratch_addr_reg != 32'd0)) begin
                                m_axi_araddr  <= desc_scratch_addr_reg;
                                m_axi_arvalid <= 1'b1;
                                state_reg     <= ST_AUX_AR;
                            end else begin
                                desc_leak_factor_reg <= 16'd0;
                                output_word_idx_reg  <= 32'd0;
                                state_reg            <= ST_PREP_OUTPUT;
                            end
                        end else begin
                            input_fetch_idx_reg <= input_fetch_idx_reg + 32'd1;
                            m_axi_araddr        <= desc_input_addr_reg + ((input_fetch_idx_reg + 32'd1) << 2);
                            m_axi_arvalid       <= 1'b1;
                            state_reg           <= ST_INPUT_AR;
                        end
                    end
                end

                ST_AUX_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_AUX_R;
                    end
                end

                ST_AUX_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready          <= 1'b0;
                        desc_leak_factor_reg  <= m_axi_rdata[15:0];
                        output_word_idx_reg   <= 32'd0;
                        state_reg             <= ST_PREP_OUTPUT;
                    end
                end

                ST_Y_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_Y_R;
                    end
                end

                ST_Y_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready  <= 1'b0;
                        aux_y_word_reg <= m_axi_rdata;
                        core_reset_req <= 1'b1;
                        state_reg      <= ST_CORE_RESET;
                    end
                end

                ST_PREP_OUTPUT: begin
                    captured_out0_reg      <= 16'd0;
                    captured_out1_reg      <= 16'd0;
                    captured_out0_seen_reg <= 1'b0;
                    captured_out1_seen_reg <= 1'b0;
                    ub_readback_out0_reg   <= 16'd0;
                    ub_readback_out1_reg   <= 16'd0;
                    ub_readback_out0_seen_reg <= 1'b0;
                    ub_readback_out1_seen_reg <= 1'b0;
                    param_word_idx_reg     <= 2'd0;
                    tile_word_idx_reg      <= 32'd0;
                    param_word0_reg        <= 32'd0;
                    param_word1_reg        <= 32'd0;
                    param_word2_reg        <= 32'd0;
                    aux_y_word_reg         <= 32'd0;
                    if(transition_mse_enable) begin
                        m_axi_araddr    <= desc_scratch_addr_reg + (output_word_idx_reg << 2);
                        m_axi_arvalid   <= 1'b1;
                        state_reg       <= ST_Y_AR;
                    end else begin
                        core_reset_req   <= 1'b1;
                        state_reg        <= ST_CORE_RESET;
                    end
                end

                ST_CORE_RESET: begin
                    param_word_idx_reg <= 2'd0;
                    m_axi_araddr       <= current_tile_param_word0_addr;
                    m_axi_arvalid      <= 1'b1;
                    state_reg          <= ST_PARAM_AR;
                end

                ST_PARAM_AR: begin
                    if(m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state_reg     <= ST_PARAM_R;
                    end
                end

                ST_PARAM_R: begin
                    if(m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        case(param_word_idx_reg)
                            2'd0: param_word0_reg <= m_axi_rdata;
                            2'd1: param_word1_reg <= m_axi_rdata;
                            2'd2: param_word2_reg <= m_axi_rdata;
                            default: begin end
                        endcase
                        param_fetch_word_count_reg <= param_fetch_word_count_reg + 32'd1;
                        param_checksum_reg         <= param_checksum_reg + m_axi_rdata;
                        param_last_word_reg        <= m_axi_rdata;

                        if(param_word_idx_reg == 2'd0) begin
                            param_word_idx_reg <= 2'd1;
                            m_axi_araddr       <= current_tile_param_word1_addr;
                            m_axi_arvalid      <= 1'b1;
                            state_reg          <= ST_PARAM_AR;
                        end else if(param_word_idx_reg == 2'd1) begin
                            if(tile_word_idx_reg == 32'd0) begin
                                param_word_idx_reg <= 2'd2;
                                m_axi_araddr       <= current_output_bias_param_addr;
                                m_axi_arvalid      <= 1'b1;
                                state_reg          <= ST_PARAM_AR;
                            end else begin
                                param_word2_reg <= 32'd0;
                                start_fe_write(TPU_FE_REG_LEAK, {16'd0, desc_leak_factor_reg});
                                state_reg <= ST_FE_CFG_LEAK;
                            end
                        end else begin
                            start_fe_write(TPU_FE_REG_LEAK, {16'd0, desc_leak_factor_reg});
                            state_reg <= ST_FE_CFG_LEAK;
                        end
                    end
                end

                ST_FE_CFG_LEAK: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_INV_BATCH, {16'd0, current_inv_batch_factor});
                        state_reg <= ST_FE_CFG_INV_BATCH;
                    end
                end
                ST_FE_CFG_INV_BATCH: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_LR, 32'd0);
                        state_reg <= ST_FE_CFG_LR;
                    end
                end
                ST_FE_CFG_LR: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, current_input_word[15:0]});
                        state_reg <= ST_FE_LOAD_X0;
                    end
                end
                ST_FE_LOAD_X0: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0001);
                        state_reg <= ST_FE_PUSH_X0;
                    end
                end
                ST_FE_PUSH_X0: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, current_input_word[31:16]});
                        state_reg <= ST_FE_LOAD_X1;
                    end
                end
                ST_FE_LOAD_X1: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0001);
                        state_reg <= ST_FE_PUSH_X1;
                    end
                end
                ST_FE_PUSH_X1: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, param_word0_reg[31:16]});
                        state_reg <= ST_FE_LOAD_W00;
                    end
                end
                ST_FE_LOAD_W00: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA1, {16'd0, param_word0_reg[15:0]});
                        state_reg <= ST_FE_LOAD_W01;
                    end
                end
                ST_FE_LOAD_W01: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0003);
                        state_reg <= ST_FE_PUSH_W0;
                    end
                end
                ST_FE_PUSH_W0: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, param_word1_reg[31:16]});
                        state_reg <= ST_FE_LOAD_W10;
                    end
                end
                ST_FE_LOAD_W10: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA1, {16'd0, param_word1_reg[15:0]});
                        state_reg <= ST_FE_LOAD_W11;
                    end
                end
                ST_FE_LOAD_W11: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0003);
                        state_reg <= ST_FE_PUSH_W1;
                    end
                end
                ST_FE_PUSH_W1: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, current_bias_word[31:16]});
                        state_reg <= ST_FE_LOAD_B0;
                    end
                end
                ST_FE_LOAD_B0: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA1, {16'd0, current_bias_word[15:0]});
                        state_reg <= ST_FE_LOAD_B1;
                    end
                end
                ST_FE_LOAD_B1: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0003);
                        state_reg <= ST_FE_PUSH_B;
                    end
                end
                ST_FE_PUSH_B: begin
                    if(fe_write_done_reg) begin
                        if(transition_mse_enable && current_tile_pathway[1]) begin
                            start_fe_write(TPU_FE_REG_UB_DATA0, {16'd0, aux_y_word_reg[31:16]});
                            state_reg <= ST_FE_LOAD_Y0;
                        end else begin
                            state_reg <= ST_FE_START;
                        end
                    end
                end
                ST_FE_LOAD_Y0: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_DATA1, {16'd0, aux_y_word_reg[15:0]});
                        state_reg <= ST_FE_LOAD_Y1;
                    end
                end
                ST_FE_LOAD_Y1: begin
                    if(fe_write_done_reg) begin
                        start_fe_write(TPU_FE_REG_UB_PUSH, 32'h0000_0003);
                        state_reg <= ST_FE_PUSH_Y;
                    end
                end
                ST_FE_PUSH_Y: begin
                    if(fe_write_done_reg) begin
                        state_reg <= ST_FE_START;
                    end
                end
                ST_FE_START: begin
                    captured_out0_reg      <= 16'd0;
                    captured_out1_reg      <= 16'd0;
                    captured_out0_seen_reg <= 1'b0;
                    captured_out1_seen_reg <= 1'b0;
                    tile_exec_valid        <= 1'b1;
                    if(tile_exec_ready) begin
                        state_reg <= ST_FE_STATUS_WAIT;
                    end
                end
                ST_FE_STATUS_WAIT: begin
                    if(tile_exec_done) begin
                        if(captured_out0_seen_reg && captured_out1_seen_reg) begin
                            if(tile_word_idx_reg + 32'd1 >= desc_input_words_reg) begin
                                ub_readback_out0_seen_reg <= 1'b0;
                                ub_readback_out1_seen_reg <= 1'b0;
                                state_reg <= ST_FE_RB_LOAD;
                            end else begin
                                tile_word_idx_reg  <= tile_word_idx_reg + 32'd1;
                                param_word_idx_reg <= 2'd0;
                                param_word0_reg    <= 32'd0;
                                param_word1_reg    <= 32'd0;
                                param_word2_reg    <= 32'd0;
                                core_reset_req     <= 1'b1;
                                state_reg          <= ST_CORE_RESET;
                            end
                        end else begin
                            status_error <= 1'b1;
                            status_busy  <= 1'b0;
                            state_reg    <= ST_FAIL;
                        end
                    end
                end

                ST_FE_RB_LOAD: begin
                    readback_exec_valid <= 1'b1;
                    if(readback_exec_ready) begin
                        state_reg <= ST_FE_RB_WAIT;
                    end
                end


                ST_FE_RB_WAIT: begin
                    if(ub_readback_out0_seen_reg && ub_readback_out1_seen_reg) begin
                        m_axi_awaddr  <= desc_output_addr_reg + (output_word_idx_reg << 2);
                        m_axi_awvalid <= 1'b1;
                        state_reg     <= ST_AXI_WB_AW;
                    end
                end

                ST_AXI_WB_AW: begin
                    m_axi_awaddr  <= desc_output_addr_reg + (output_word_idx_reg << 2);
                    m_axi_awvalid <= 1'b1;
                    if(m_axi_awready) begin
                        state_reg <= ST_AXI_WB_W;
                    end
                end
                ST_AXI_WB_W: begin
                    m_axi_wdata  <= final_output_word;
                    m_axi_wstrb  <= 4'hf;
                    m_axi_wlast  <= 1'b1;
                    m_axi_wvalid <= 1'b1;
                    if(m_axi_wready) begin
                        state_reg <= ST_AXI_WB_B;
                    end
                end
                ST_AXI_WB_B: begin
                    m_axi_bready <= 1'b1;
                    if(m_axi_bvalid) begin
                        if(output_word_idx_reg + 32'd1 >= desc_output_words_reg) begin
                            status_busy <= 1'b0;
                            status_done <= 1'b1;
                            state_reg   <= ST_DONE;
                        end else begin
                            output_word_idx_reg <= output_word_idx_reg + 32'd1;
                            state_reg           <= ST_PREP_OUTPUT;
                        end
                    end
                end

                ST_DONE: begin
                    state_reg <= ST_IDLE;
                end

                ST_FAIL: begin
                    state_reg <= ST_IDLE;
                end

                default: begin
                    status_error <= 1'b1;
                    status_busy  <= 1'b0;
                    state_reg    <= ST_FAIL;
                end
            endcase
        end
    end

    wire unused_ok;
    assign unused_ok = &{
        1'b0,
        m_axi_bresp[0],
        m_axi_rresp[0],
        m_axi_rlast,
        fe_cmd_ready,
        fe_rsp_valid,
        ub_rd_y_data_out_0[0],
        ub_rd_y_data_out_1[0],
        ub_rd_y_valid_out_0,
        ub_rd_y_valid_out_1
    };

endmodule

`default_nettype wire
