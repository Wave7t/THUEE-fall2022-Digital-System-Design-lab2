module PE_term #(
    parameter IN_BW_D = 8,
    parameter IN_BW_S = 8,
    parameter ACCU_BW = 24
) (
    input   clk,
    input   rst_n,
    input   reset_weight,
    // input   calc_enable,
    input   signed   [IN_BW_D-1:0]   IN_flow,
    input   signed   [IN_BW_S-1:0]   IN_stat,
    input   signed   [ACCU_BW-1:0]   ACCU_IN,
    output  signed   [ACCU_BW-1:0]   ACCU_OUT
);
    // Weight Storage
    reg signed [IN_BW_S-1:0] Stored_W;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            Stored_W <= 0;
        end else if (reset_weight) begin
            Stored_W <= IN_stat;
        end else begin
            Stored_W <= Stored_W;
        end
    end

    // Accumulation
    reg signed [ACCU_BW-1:0] ACCU_BUF;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            ACCU_BUF <= 0;
        end
        else begin
            ACCU_BUF <= ACCU_IN + IN_flow * Stored_W;
        end
        // else if (calc_enable) begin
        //     ACCU_BUF <= ACCU_IN + IN_flow * Stored_W;
        // end
        // else begin
        //     ACCU_BUF <= ACCU_IN;
        // end
    end

    assign ACCU_OUT = ACCU_BUF;

endmodule

// This module is verified
module delayer_v1 #(
    parameter BW = 8,
    parameter N_STAGE = 5
) (
    input   clk,
    input   rst_n,
    input   [BW-1:0] data_in,
    output  [BW-1:0] data_out
);

    reg [BW-1:0] stages [N_STAGE-1:0];
    wire [BW-1:0] inter_stage_in [N_STAGE-1:0];
    assign inter_stage_in[0] = data_in;

    // connecting outputs
    generate
        genvar n_output;
        for (n_output = 1; n_output < N_STAGE; n_output = n_output + 1) begin
            assign inter_stage_in[n_output] = stages[n_output - 1];
        end
    endgenerate
    assign data_out = stages[N_STAGE-1];

    // connecting inputs
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (integer n = 0; n < N_STAGE; n = n + 1) begin
                stages[n] <= 0;
            end
        end
        else begin
            for (integer n = 0; n < N_STAGE; n = n + 1) begin
                stages[n] <= inter_stage_in[n];
            end
        end
    end

endmodule


module Systolic_Array_1D #(
    parameter N = 10,
    parameter IA_BW = 8,
    parameter WT_BW = 8,
    parameter ACC_BW = 32
) (
    input   clk,
    input   rst_n,
    input   reset_weight,
    input   signed  [IA_BW-1:0] IA [N-1:0],
    input   signed  [WT_BW-1:0] WT [N-1:0],
    output  signed  [ACC_BW-1:0] out
);

    wire signed [ACC_BW-1:0]    inter_pe_accum  [N:0];
    reg  signed [IA_BW-1:0]     ia_buf          [N-1:0];
    wire signed [IA_BW-1:0]     wire_delay2pe   [N-1:0];
    reg  signed [WT_BW-1:0]     wt_buf          [N-1:0];
    wire signed [WT_BW-1:0]     wire_wtbuf2pe   [N-1:0];
    reg                         reset_wt_buf;   

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer n = 0; n < N; n = n + 1) begin
                ia_buf[n] <= 0;
                wt_buf[n] <= 0;
            end
            reset_wt_buf <= 0;
        end
        else begin
            for (integer n = 0; n < N; n = n + 1) begin
                ia_buf[n] <= IA[n];
                wt_buf[n] <= WT[n];
            end
            reset_wt_buf <= reset_weight;
        end
    end

generate
    genvar n_ia;
    for (n_ia = 0; n_ia < N; n_ia = n_ia + 1) begin : delayers
        delayer #(
            IA_BW, n_ia
        ) pipeline_reg (
            .clk(clk),
            .rst_n(rst_n),
            .data_in(ia_buf[n_ia]),
            .data_out(wire_delay2pe[n_ia])
        );
    end
endgenerate

generate
    genvar n_pe;
    for (n_pe = 0; n_pe < N; n_pe = n_pe + 1) begin : pe_array
        PE_term #(
            IA_BW, WT_BW, ACC_BW
        ) pe (
            .clk(clk),
            .rst_n(rst_n),
            .reset_weight(reset_wt_buf),
            .IN_flow(wire_delay2pe[n_pe]),
            .IN_stat(wt_buf[n_pe]),
            .ACCU_IN(inter_pe_accum[n_pe]),
            .ACCU_OUT(inter_pe_accum[n_pe + 1])
        );
    end
endgenerate

reg [ACC_BW-1:0] accum_begin;
always @(negedge rst_n) accum_begin <= 0;

assign inter_pe_accum[0] = accum_begin;
assign out = inter_pe_accum[N];

endmodule

