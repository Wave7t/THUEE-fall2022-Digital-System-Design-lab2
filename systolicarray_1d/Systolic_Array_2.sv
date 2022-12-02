module clip_v1 #(
    parameter INPUT_BW = 32,
    parameter TARGET_BW = 8
) (
    input  signed [INPUT_BW-1:0]  data_in,
    output reg signed [TARGET_BW-1:0] data_out
);
    localparam MAX = 2**(TARGET_BW-1)-1;
    localparam MIN = -2**(TARGET_BW-1);

    always @(*) begin
        if (data_in > MAX) begin
            data_out <= MAX;
        end
        else if (data_in < MIN) begin
            data_out <= MIN;
        end
        else begin
            data_out <= data_in[TARGET_BW-1:0];
        end
    end

endmodule

module PE_term_2 #(
    parameter IN_BW_WT = 8,
    parameter IN_BW_IA = 8,
    parameter IN_BW_MAX = 8,
    parameter ACCU_BW = 24
) (
    input   clk,
    input   rst_n,
    input   [IN_BW_MAX-1:0] IN,
    input   reset_weight,
    input   signed      [ACCU_BW-1:0]   ACCU_IN,
    output  signed      [ACCU_BW-1:0]   ACCU_OUT
);

    // decompose the input
    wire signed [IN_BW_IA-1:0] IA_IN = IN[IN_BW_IA-1:0];
    wire signed [IN_BW_WT-1:0] WT_IN = IN[IN_BW_WT-1:0];

    // Weight Storage
    reg signed [IN_BW_WT-1:0] Stored_W;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            Stored_W <= 0;
        end else if (reset_weight) begin
            Stored_W <= WT_IN;
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
            ACCU_BUF <= ACCU_IN + IA_IN * Stored_W;
        end
    end

    assign ACCU_OUT = ACCU_BUF;

endmodule


/* 
IN_BW_MAX should be the bigger og IN_BW_WT and IN_BW_IA 
****************************************************************
Bebavioural description:
- apply `IN`, and receive output after N clock cycles
- apply `IN` and `reset_weight`, then apply the new IA next cycle

all these are designed to keep the pipeline full
*/
module Systolic_Array_1D_v2 #(
    parameter N = 10,
    parameter IA_BW = 4,
    parameter WT_BW = 4,
    parameter MM_BW = 4,
    parameter ACC_BW = 16
) (

    input   clk,
    input   rst_n,

    input   reset_weight,
    input   [MM_BW-1:0] IN [N-1:0],

    input   specified_accum_in,
    output  [7:0] out
);

    // inter-pe
    wire signed [ACC_BW-1:0]    inter_pe_accum  [N:0];
    wire signed [ACC_BW-1:0]    out_full;
    
    clip_v1 #(
        ACC_BW, 8
    ) c (
        out_full, out
    );

    // interface to pe 
    // - highest bit: reset_weight
    // - lower bits:  data
    reg         [MM_BW:0]       ibuf            [N-1:0];
    wire        [MM_BW:0]       wire_delay2pe   [N-1:0];

    // general input buffer
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (integer n = 0; n < N; n = n + 1) begin
                ibuf[n] <= 0;
            end
        end
        else begin
            for (integer n = 0; n < N; n = n + 1) begin
                ibuf[n][MM_BW-1:0] <= IN[n];
                ibuf[n][MM_BW] <= reset_weight;
            end
        end
    end

    // delays
    assign wire_delay2pe[0] = ibuf[0];
generate
    genvar n_ia;
    for (n_ia = 1; n_ia < N; n_ia = n_ia + 1) begin : delayers
        delayer #(
            MM_BW+1, n_ia
        ) pipeline_reg (
            .clk(clk),
            .rst_n(rst_n),
            .data_in(ibuf[n_ia]),
            .data_out(wire_delay2pe[n_ia])
        );
    end
endgenerate

    // PE array
generate
    genvar n_pe;
    for (n_pe = 0; n_pe < N; n_pe = n_pe + 1) begin : pe_array
        PE_term_2 #(
            IA_BW, WT_BW, MM_BW, ACC_BW
        ) pe (
            .clk(clk),
            .rst_n(rst_n),
            .IN(wire_delay2pe[n_pe][MM_BW-1:0]),
            .reset_weight(wire_delay2pe[n_pe][MM_BW]),
            .ACCU_IN(inter_pe_accum[n_pe]),
            .ACCU_OUT(inter_pe_accum[n_pe + 1])
        );
    end
endgenerate

// head of accumulation
reg [ACC_BW-1:0] accum_begin;
always @(*) begin
    if (specified_accum_in) begin
        accum_begin <= out_full;
    end
    else begin
        accum_begin <= 0;
    end
end
assign inter_pe_accum[0] = accum_begin;

// end of accumulation
assign out_full = inter_pe_accum[N];

endmodule

