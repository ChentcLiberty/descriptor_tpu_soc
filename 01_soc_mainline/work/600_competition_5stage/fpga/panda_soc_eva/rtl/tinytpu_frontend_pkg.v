package tinytpu_frontend_pkg;

    localparam logic [11:0] TPU_FE_REG_CTRL       = 12'h000;
    localparam logic [11:0] TPU_FE_REG_STATUS     = 12'h004;
    localparam logic [11:0] TPU_FE_REG_INSTR_W0   = 12'h010;
    localparam logic [11:0] TPU_FE_REG_UB_DATA0   = 12'h020;
    localparam logic [11:0] TPU_FE_REG_UB_PUSH    = 12'h024;
    localparam logic [11:0] TPU_FE_REG_UB_DATA1   = 12'h028;
    localparam logic [11:0] TPU_FE_REG_IMEM_ADDR  = 12'h030;
    localparam logic [11:0] TPU_FE_REG_IMEM_W0    = 12'h034;
    localparam logic [11:0] TPU_FE_REG_IMEM_WE    = 12'h040;
    localparam logic [11:0] TPU_FE_REG_IMEM_LEN   = 12'h044;
    localparam logic [11:0] TPU_FE_REG_LEAK       = 12'h050;
    localparam logic [11:0] TPU_FE_REG_INV_BATCH  = 12'h054;
    localparam logic [11:0] TPU_FE_REG_LR         = 12'h058;

    localparam logic [31:0] TPU_FE_CTRL_STEP  = 32'h0000_0001;
    localparam logic [31:0] TPU_FE_CTRL_START = 32'h0000_0002;

    localparam logic [2:0] TPU_FE_OP_NOP        = 3'b000;
    localparam logic [2:0] TPU_FE_OP_SWITCH     = 3'b001;
    localparam logic [2:0] TPU_FE_OP_UB_RD      = 3'b010;
    localparam logic [2:0] TPU_FE_OP_UB_WR_HOST = 3'b011;

    localparam logic [2:0] TPU_FE_PTR_INPUT      = 3'd0;
    localparam logic [2:0] TPU_FE_PTR_WEIGHT     = 3'd1;
    localparam logic [2:0] TPU_FE_PTR_BIAS       = 3'd2;
    localparam logic [2:0] TPU_FE_PTR_Y          = 3'd3;
    localparam logic [2:0] TPU_FE_PTR_H          = 3'd4;
    localparam logic [2:0] TPU_FE_PTR_GRAD_BIAS  = 3'd5;
    localparam logic [2:0] TPU_FE_PTR_GRAD_WEIGHT= 3'd6;

    function automatic logic [31:0] tinytpu_instr_nop();
        tinytpu_instr_nop = 32'h0000_0000;
    endfunction

    function automatic logic [31:0] tinytpu_instr_switch();
        tinytpu_instr_switch = {29'd0, TPU_FE_OP_SWITCH};
    endfunction

    function automatic logic [31:0] tinytpu_instr_ub_rd(
        input logic [5:0] addr,
        input logic [3:0] row,
        input logic [1:0] col,
        input logic       transpose,
        input logic [2:0] ptr_sel,
        input logic [3:0] vpu_pathway
    );
        tinytpu_instr_ub_rd = {
            9'd0,
            vpu_pathway,
            ptr_sel,
            transpose,
            col,
            row,
            addr,
            TPU_FE_OP_UB_RD
        };
    endfunction

    function automatic logic [31:0] tinytpu_instr_ub_wr_host(
        input logic [15:0] data
    );
        tinytpu_instr_ub_wr_host = {13'd0, data, TPU_FE_OP_UB_WR_HOST};
    endfunction

endpackage
