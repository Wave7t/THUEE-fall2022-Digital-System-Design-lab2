module DualBuffer #(
    parameter BW = 8,
    parameter N = 8,
    parameter CNT_BW = 3,
    parameter INDEX = 0
) (
    input   clk,
    input   rst_n,
    input   switch,
    input   [CNT_BW-1:0] cnt,
    input   signed    [BW-1:0] parallel_in    [N-1:0],
    output  reg signed [BW-1:0] parallel_out   [N-1:0]
);
    reg signed [BW-1:0] buffer_0 [N-1:0];
    reg signed [BW-1:0] buffer_1 [N-1:0];

    reg [1:0] is_active_for_output;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (integer k = 0; k < N; k = k + 1) begin
                buffer_0[k] <= 0;
                buffer_1[k] <= 0;
            end
            is_active_for_output <= 2'b1;
        end
        else begin
            for (integer k = 0; k < N; k = k + 1) begin
                if (is_active_for_output[0] && (cnt == INDEX)) buffer_1[k] <= parallel_in[k];
                else buffer_1[k] <= buffer_1[k];
            end
            for (integer k = 0; k < N; k = k + 1) begin
                if (is_active_for_output[1] && (cnt == INDEX)) buffer_0[k] <= parallel_in[k];
                else buffer_0[k] <= buffer_0[k];
            end
            if (switch) begin
                is_active_for_output <= ~is_active_for_output;
            end
        end
    end

    always @(*) begin
        for (integer cnt_output = 0; cnt_output < N; cnt_output = cnt_output + 1) begin
            if (is_active_for_output[0]) parallel_out[cnt_output] <= buffer_0[cnt_output];
            else parallel_out[cnt_output] <= buffer_1[cnt_output];
        end
    end
endmodule


module AdderTreeRow #(
    parameter N_LAYER = 3,
    parameter IA_BW = 8,
    parameter WT_BW = 8
) (
    input   clk,
    input   rst_n,
    input   signed [IA_BW-1:0] IA_IN [2**N_LAYER-1:0],
    input   signed [WT_BW-1:0] WT_IN [2**N_LAYER-1:0],
    output  signed [IA_BW+WT_BW+N_LAYER-1:0] DATA_OUT
);

    localparam POST_MUL_BW = IA_BW + WT_BW;
    localparam POST_ADD_BW = POST_MUL_BW + N_LAYER;
    localparam SIZE = 2**N_LAYER;
    localparam N_STAGE = 4;

    reg signed [POST_MUL_BW-1:0] buf_mul_add [SIZE-1:0];
    wire signed [POST_ADD_BW-1:0] adder_tree_out;
    reg signed [POST_ADD_BW-1:0] buf_add_out;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (integer n = 0; n < SIZE; n = n + 1) begin
                buf_mul_add[n] <= 0;
            end
            buf_add_out <= 0;
        end
        else begin
            for (integer n = 0; n < SIZE; n = n + 1) begin
                buf_mul_add[n] <= IA_IN[n] * WT_IN[n];
            end
            buf_add_out <= adder_tree_out;
        end
    end

    Adder_Tree #(POST_MUL_BW, N_LAYER, SIZE, POST_ADD_BW) addt (
        .operands(buf_mul_add),
        .result(adder_tree_out)
    );

    assign DATA_OUT = buf_add_out;

endmodule

module OutputBuffer #(
    parameter BW = 8,
    parameter M = 8,
    parameter SIZE = 32,
    parameter IDX_BW = 3
) (
    input   clk,
    input   wr_enable,
    input   [IDX_BW-1:0] addr_in,
    input   [IDX_BW-1:0] addr_out,
    input   signed [BW-1:0] data_in [M-1:0],
    output  signed [BW-1:0] data_out [M-1:0]
);
    reg signed [BW-1:0] data [SIZE-1:0][M-1:0];

    always @(posedge clk) begin
        if (wr_enable) for (integer n = 0; n < M; n = n + 1) begin
            data[addr_in][n] <= data_in[n];
        end
    end

    generate
        genvar k;
        for (k = 0; k < M; k = k + 1) begin
            assign data_out[k] = data[addr_out][k];
        end
    endgenerate

endmodule


module mactree_2d #(
    parameter IA_BW = 8,
    parameter WT_BW = 8,
    parameter ACCU_BW = 24,

    parameter OABUFSZ = 20,
    parameter M = 8,
    parameter N_LAYER = 3
) (
    input   clk,
    input   rst_n,

    input   signed [WT_BW-1:0] WT_IN   [2**N_LAYER-1:0],
    input   weight_update_start,

    input   signed [IA_BW-1:0] IA_IN   [2**N_LAYER-1:0],
    input   calc_start,
    input   calc_start_resume,

    output  signed [IA_BW-1:0] OA_OUT  [M-1:0],
    output  outputing    
);

    localparam N = 2**N_LAYER;
    localparam CNT_BW = 5;
    localparam M_CNT_BW = 4;
    localparam PIPELINE_DELAY = 4;

    // weight update control
    wire [CNT_BW-1:0] selected_weight_idx;
    wire is_counting;
    Counter #(CNT_BW, M) weight_ind_cnt (
        .clk(clk),
        .rst_n(rst_n),
        .start(weight_update_start),
        .cur_val(selected_weight_idx),
        .is_counting(is_counting)
    );

    // buffer input activation
    reg signed [IA_BW-1:0] IA_input_buf [N-1:0];
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) for (integer n = 0; n < N; n = n + 1) IA_input_buf[n] <= 0;
        else        for (integer n = 0; n < N; n = n + 1) IA_input_buf[n] <= IA_IN[n];
    end

    wire [CNT_BW-1:0] cnt_temp;

    localparam CNT_DELAY_IN2RD = 2;
    wire [CNT_BW-1:0] OA_Addr_rd;

    localparam CNT_DELAY_RD2WB = 2;
    wire [CNT_BW-1:0] OA_Addr_wb;

    delayer_v1 #(CNT_BW, CNT_DELAY_IN2RD) delayer_cnt_1 (clk, rst_n, cnt_temp, OA_Addr_rd);
    delayer_v1 #(CNT_BW, CNT_DELAY_RD2WB) delayer_cnt_2 (clk, rst_n, OA_Addr_rd, OA_Addr_wb);

    wire IA_available, OA_available, outputing_valid;
    SFT_REG #(CNT_DELAY_IN2RD + CNT_DELAY_RD2WB - 1) delayer_wren_1 (clk, rst_n, IA_available, outputing_valid);
    SFT_REG #(1) delayer_wren_2 (clk, rst_n, outputing_valid, OA_available);

    Counter #(CNT_BW, OABUFSZ) oa_ind_cnt (
        .clk(clk),
        .rst_n(rst_n),
        .start(calc_start),
        .cur_val(cnt_temp),
        .is_counting(IA_available)
    );

    reg signed [ACCU_BW-1:0] OA_WB_BUF [M-1:0];
    reg signed [ACCU_BW-1:0] OA_RD_BUF [M-1:0];
    wire signed [ACCU_BW-1:0] OA_readout [M-1:0];
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) for (integer n = 0; n < N; n = n + 1) OA_RD_BUF[n] <= 0;
        else        for (integer n = 0; n < N; n = n + 1) OA_RD_BUF[n] <= OA_readout[n];
    end
    OutputBuffer #(ACCU_BW, M, OABUFSZ, CNT_BW) oabuf (
        .clk(clk),
        .wr_enable(OA_available),
        .addr_in(OA_Addr_wb),
        .addr_out(OA_Addr_rd),
        .data_in(OA_WB_BUF),
        .data_out(OA_readout)
    );

    localparam DELAY_MAC = 3;
    wire mac_resume;
    SFT_REG #(DELAY_MAC) delayer_resume (clk, rst_n, calc_start_resume, mac_resume);

    wire signed [IA_BW+WT_BW+N_LAYER-1:0] pe_out [M-1:0];
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) for (integer n = 0; n < N; n = n + 1) OA_WB_BUF[n] <= 0;
        else        for (integer n = 0; n < N; n = n + 1) begin
            if (mac_resume) OA_WB_BUF[n] <= OA_RD_BUF[n] + pe_out[n];
            else            OA_WB_BUF[n] <= pe_out[n];
        end
    end

    // automatic switching machanism
    reg weight_switch_ready;
    reg is_counting_prev;
    // always @(posedge clk or negedge rst_n) begin
    //     if (~rst_n) begin
    //         weight_switch_ready <= 0;
    //         is_counting_prev <= 0;
    //     end
    //     else begin
    //         is_counting_prev <= is_counting;
    //         if (weight_switch_ready) weight_switch_ready <= 0;
    //         else begin
    //             if (is_counting_prev && ~is_counting) weight_switch_ready <= 1;
    //             else weight_switch_ready <= 0;
    //         end
    //     end
    // end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            weight_switch_ready <= 0;
            is_counting_prev <= 0;
        end
        else begin
            is_counting_prev <= is_counting;
            if (calc_start) weight_switch_ready <= 0;
            else begin
                if (is_counting_prev && ~is_counting) weight_switch_ready <= 1;
                else weight_switch_ready <= weight_switch_ready;
            end
        end
    end

    generate
        genvar n_wbuf;
        for (n_wbuf = 0; n_wbuf < M; n_wbuf = n_wbuf + 1) begin : weight_buffer
            wire signed [WT_BW-1:0] weight_out_port [N-1:0];
            
            DualBuffer #(WT_BW, N, CNT_BW, n_wbuf) wbuf (
                .clk(clk), .rst_n(rst_n),
                .switch(weight_switch_ready && calc_start),
                .cnt(selected_weight_idx),
                .parallel_in(WT_IN),
                .parallel_out(weight_out_port)
            );
        end
    endgenerate

    // Functioning Unit
    generate
        genvar mtcnt;
        for (mtcnt = 0; mtcnt < M; mtcnt = mtcnt + 1) begin : addertrees
            AdderTreeRow #(N_LAYER, IA_BW, WT_BW) addtrow (
                .clk(clk),
                .rst_n(rst_n),
                .IA_IN(IA_input_buf),
                .WT_IN(weight_buffer[mtcnt].weight_out_port),
                .DATA_OUT(pe_out[mtcnt])
            );
        end
    endgenerate

    generate
        genvar nout;
        for (nout = 0; nout < M; nout = nout + 1) begin : clips
            clip_v1 #(ACCU_BW, 8) clip_output (OA_RD_BUF[nout] >>> 8, OA_OUT[nout]);
        end
    endgenerate

    assign outputing = (~mac_resume) && outputing_valid;

endmodule