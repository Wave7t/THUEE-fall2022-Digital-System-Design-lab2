`ifndef DELAYER_H
`define DELAYER_H

// This module is verified
module delayer #(
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


`endif