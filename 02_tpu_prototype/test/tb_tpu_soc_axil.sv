`timescale 1ns/1ps
`default_nettype none

// Testbench for tpu_soc AXI-Lite with 32-bit opcode instructions
module tb_tpu_soc_axil;

    logic        clk, aresetn;
    logic [11:0] awaddr;  logic awvalid; logic awready;
    logic [31:0] wdata;   logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0]  bresp;   logic bvalid;  logic bready;
    logic [11:0] araddr;  logic arvalid; logic arready;
    logic [31:0] rdata;   logic [1:0] rresp; logic rvalid; logic rready;
    logic [15:0] vpu_data_out_1, vpu_data_out_2;
    logic        vpu_valid_out_1, vpu_valid_out_2;
    logic [15:0] sys_data_out_21, sys_data_out_22;
    logic        sys_valid_out_21, sys_valid_out_22;

    tpu_soc #(.SYSTOLIC_ARRAY_WIDTH(2)) dut (
        .s_axil_aclk(clk), .s_axil_aresetn(aresetn),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata),   .s_axil_wstrb(wstrb),    .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp),   .s_axil_bvalid(bvalid),  .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid),.s_axil_arready(arready),
        .s_axil_rdata(rdata),   .s_axil_rresp(rresp),    .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .vpu_data_out_1(vpu_data_out_1), .vpu_data_out_2(vpu_data_out_2),
        .vpu_valid_out_1(vpu_valid_out_1), .vpu_valid_out_2(vpu_valid_out_2),
        .sys_data_out_21(sys_data_out_21), .sys_data_out_22(sys_data_out_22),
        .sys_valid_out_21(sys_valid_out_21), .sys_valid_out_22(sys_valid_out_22)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    `define AXIL_WRITE(ADDR, DATA) \
        @(posedge clk); #1; \
        awaddr  = ADDR; awvalid = 1; \
        wdata   = DATA; wstrb   = 4'hF; wvalid = 1; bready = 1; \
        @(posedge clk); #1; \
        awvalid = 0; wvalid = 0; \
        while (!bvalid) @(posedge clk); \
        #1; bready = 0; \
        while (bvalid) @(posedge clk); \
        #1;

    `define AXIL_READ(ADDR, DOUT) \
        @(posedge clk); #1; \
        araddr = ADDR; arvalid = 1; rready = 1; \
        while (!rvalid) @(posedge clk); \
        #1; DOUT = rdata; arvalid = 0; \
        @(posedge clk); #1; \
        rready = 0; \
        @(posedge clk); #1;

    // 32-bit opcode instruction encodings
    // NOP:    32'h00000000
    // SWITCH: 32'h00000001  (opcode=001)
    // UB_RD:  opcode=010, [8:3]=addr, [12:9]=row, [14:13]=col, [15]=transpose,
    //                     [18:16]=ptr_sel, [22:19]=vpu_pathway
    // Example: UB_RD ptr_sel=1, addr=12, row=2, col=2, transpose=1
    //   = opcode=010 | addr=12<<3 | row=2<<9 | col=2<<13 | transpose=1<<15 | ptr_sel=1<<16
    //   = 3'b010 | (12<<3) | (2<<9) | (2<<13) | (1<<15) | (1<<16)

    integer pass_count, fail_count;
    logic [31:0] rd_data;

    initial begin
        aresetn = 0;
        awvalid = 0; wvalid = 0; bready = 0;
        arvalid = 0; rready = 0;
        awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
        pass_count = 0; fail_count = 0;

        repeat(4) @(posedge clk);
        aresetn = 1;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------------
        // Test 1: Write/read INSTR_W0 (single 32-bit opcode)
        // ------------------------------------------------------------------
        $display("[TEST] Write/read INSTR_W0 (32-bit opcode)");
        `AXIL_WRITE(12'h010, 32'hAABBCCDD)

        `AXIL_READ(12'h010, rd_data)
        if (rd_data === 32'hAABBCCDD) begin $display("  PASS INSTR_W0"); pass_count++; end
        else begin $display("  FAIL INSTR_W0: got %08h", rd_data); fail_count++; end

        // ------------------------------------------------------------------
        // Test 2: UB_DATA write and read back
        // ------------------------------------------------------------------
        $display("[TEST] UB_DATA write/read");
        `AXIL_WRITE(12'h020, 32'h00001234)
        `AXIL_READ(12'h020, rd_data)
        if (rd_data[15:0] === 16'h1234) begin $display("  PASS UB_DATA"); pass_count++; end
        else begin $display("  FAIL UB_DATA: got %08h", rd_data); fail_count++; end

        // ------------------------------------------------------------------
        // Test 3: UB_PUSH pulse
        // ------------------------------------------------------------------
        $display("[TEST] UB_PUSH pulse");
        `AXIL_WRITE(12'h024, 32'h00000001)
        repeat(2) @(posedge clk);
        $display("  PASS UB_PUSH (no hang)"); pass_count++;

        // ------------------------------------------------------------------
        // Test 4: CTRL.step NOP (opcode=000)
        // ------------------------------------------------------------------
        $display("[TEST] CTRL.step dispatch (NOP opcode=000)");
        `AXIL_WRITE(12'h010, 32'h00000000)
        `AXIL_WRITE(12'h000, 32'h1)
        repeat(4) @(posedge clk);
        $display("  PASS step NOP (no hang)"); pass_count++;

        // ------------------------------------------------------------------
        // Test 5: CTRL.step SWITCH (opcode=001)
        // ------------------------------------------------------------------
        $display("[TEST] CTRL.step SWITCH (opcode=001)");
        `AXIL_WRITE(12'h010, 32'h00000001)
        `AXIL_WRITE(12'h000, 32'h1)
        repeat(4) @(posedge clk);
        $display("  PASS step SWITCH (no hang)"); pass_count++;

        // ------------------------------------------------------------------
        // Test 6: IMEM write/read
        // ------------------------------------------------------------------
        $display("[TEST] IMEM_ADDR/W0/WE write and read back");
        `AXIL_WRITE(12'h030, 32'h00000005)   // IMEM_ADDR = 5
        `AXIL_WRITE(12'h034, 32'hDEADBEEF)   // IMEM_W0
        `AXIL_WRITE(12'h040, 32'h00000001)   // IMEM_WE
        `AXIL_READ(12'h030, rd_data)
        if (rd_data[5:0] === 6'd5) begin $display("  PASS IMEM_ADDR"); pass_count++; end
        else begin $display("  FAIL IMEM_ADDR: got %08h", rd_data); fail_count++; end
        `AXIL_READ(12'h034, rd_data)
        if (rd_data === 32'hDEADBEEF) begin $display("  PASS IMEM_W0"); pass_count++; end
        else begin $display("  FAIL IMEM_W0: got %08h", rd_data); fail_count++; end

        // ------------------------------------------------------------------
        // Test 7: IMEM_LEN write/read
        // ------------------------------------------------------------------
        $display("[TEST] IMEM_LEN write/read");
        `AXIL_WRITE(12'h044, 32'h0000001F)   // IMEM_LEN = 31
        `AXIL_READ(12'h044, rd_data)
        if (rd_data[5:0] === 6'd31) begin $display("  PASS IMEM_LEN"); pass_count++; end
        else begin $display("  FAIL IMEM_LEN: got %08h", rd_data); fail_count++; end

        // ------------------------------------------------------------------
        // Test 8: UB_RD opcode step (ptr_sel=1, no VPU output expected, no hang)
        // opcode=010, addr=12, row=2, col=2, transpose=1, ptr_sel=1
        // [2:0]=010 [8:3]=001100 [12:9]=0010 [14:13]=10 [15]=1 [18:16]=001
        // = 0b000_001_1_10_0010_001100_010 = check field by field
        // [2:0]  = 3'b010       = 3'h2
        // [8:3]  = 6'd12        = 6'b001100  -> bits[8:3]=001100
        // [12:9] = 4'd2         = 4'b0010    -> bits[12:9]=0010
        // [14:13]= 2'd2         = 2'b10      -> bits[14:13]=10
        // [15]   = 1
        // [18:16]= 3'd1         = 3'b001
        // = 32'h00018062 + checking...
        // addr<<3=0x60, row<<9=0x400, col<<13=0x4000, trans<<15=0x8000, ptr<<16=0x10000
        // opcode=2, addr=12->0x60, row=2->0x400, col=2->0x4000, trans=1->0x8000, ptr=1->0x10000
        // total = 2|0x60|0x400|0x4000|0x8000|0x10000 = 0x1C462
        // ------------------------------------------------------------------
        $display("[TEST] CTRL.step UB_RD ptr_sel=1 (opcode=010, no hang)");
        `AXIL_WRITE(12'h010, 32'h0001C462)
        `AXIL_WRITE(12'h000, 32'h1)
        repeat(4) @(posedge clk);
        $display("  PASS step UB_RD ptr_sel=1 (no hang)"); pass_count++;

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        repeat(4) @(posedge clk);
        $display("\n=== RESULTS: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL PASS");
        else $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
