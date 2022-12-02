// complicated, needs specialized initializer
module Adder_Tree_Pipeline #(
    parameter INPUT_BW = 8,
    parameter LAYER_NUM = 3,
    parameter ARRAY_SIZE = 8,
    parameter OUTPUT_BW = 11
) (
    input  clk,
    input  rst_n,
    input  signed [INPUT_BW-1:0] operands [ARRAY_SIZE-1:0],
    output signed [OUTPUT_BW-1:0] result
);

// insert pipeline registers in the middle
localparam PP_Stage = LAYER_NUM / 2;
localparam PP_BW = INPUT_BW + PP_Stage + 1;
localparam PP_SZ = INPUT_BW / (2**PP_Stage);
reg signed [PP_BW-1:0] pipeline_reg [PP_SZ-1:0];
wire signed [PP_BW-1:0] pipeline_reg_in [PP_SZ-1:0];
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) for (integer k = 0; k < PP_SZ; k = k + 1) pipeline_reg[k] <= 0;
    else        for (integer k = 0; k < PP_SZ; k = k + 1) pipeline_reg[k] <= pipeline_reg_in[k];
end

// to be called by the outside module
localparam latency = 1;

// Create lines (have to use generate, as array sizes and bitwidths vary with layer)
generate
    genvar i;
    for (i = 0; i < LAYER_NUM; i = i + 1) begin : Wires
        wire signed [INPUT_BW+i:0] outputs [2**(LAYER_NUM-i-1)-1:0];
    end
endgenerate

// Connect the first layer to array input
generate
    genvar k;
    for (k = 0; k < 2**(LAYER_NUM-1); k = k + 1) begin : Adders_L0
        wire signed [INPUT_BW:0] op1;
        wire signed [INPUT_BW:0] op2;
        Signed_Ext #(INPUT_BW) ext_0(operands[2*k], op1);
        Signed_Ext #(INPUT_BW) ext_1(operands[2*k+1], op2);
        assign Wires[0].outputs[k] = op1 + op2;
    end
endgenerate

// Connect these lines using adders
generate
    genvar n, m;
    // loops starts from 1 instead of 0
    for (n = 1; n < LAYER_NUM; n = n + 1) begin : Adders
        for (m = 0; m < 2**(LAYER_NUM-n-1); m = m + 1) begin : Line
            wire signed [INPUT_BW+n:0] op1;
            wire signed [INPUT_BW+n:0] op2;
            Signed_Ext #(INPUT_BW+n) ext_0(Wires[n-1].outputs[2*m], op1);
            Signed_Ext #(INPUT_BW+n) ext_1(Wires[n-1].outputs[2*m+1], op2);
            if (n == PP_Stage) begin
                assign pipeline_reg_in[2 * m] = op1;
                assign pipeline_reg_in[2 * m + 1] = op2;
                assign Wires[n].outputs[m] = pipeline_reg[2 * m] + pipeline_reg[2 * m + 1];
            end
            else assign Wires[n].outputs[m] = op1 + op2;
        end
    end
endgenerate

    assign result = Wires[LAYER_NUM-1].outputs[0];

endmodule

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// module Adder_Tree_Github_1(in_addends, out_sum);

// parameter DATA_WIDTH = 8;
// parameter LENGTH = 42;

// localparam OUT_WIDTH = DATA_WIDTH + $clog2(LENGTH);
// localparam LENGTH_A = LENGTH / 2;
// localparam LENGTH_B = LENGTH - LENGTH_A;
// localparam OUT_WIDTH_A = DATA_WIDTH + $clog2(LENGTH_A);
// localparam OUT_WIDTH_B = DATA_WIDTH + $clog2(LENGTH_B);

// input signed [DATA_WIDTH-1:0] in_addends [LENGTH];
// output signed [OUT_WIDTH-1:0] out_sum;

// generate
// 	if (LENGTH == 1) begin
// 		assign out_sum = in_addends[0];
// 	end else begin
// 		wire signed [OUT_WIDTH_A-1:0] sum_a;
// 		wire signed [OUT_WIDTH_B-1:0] sum_b;
		
// 		logic signed [DATA_WIDTH-1:0] addends_a [LENGTH_A];
// 		logic signed [DATA_WIDTH-1:0] addends_b [LENGTH_B];
		
// 		always_comb begin
// 			for (int i = 0; i < LENGTH_A; i++) begin
// 				addends_a[i] = in_addends[i];
// 			end
			
// 			for (int i = 0; i < LENGTH_B; i++) begin
// 				addends_b[i] = in_addends[i + LENGTH_A];
// 			end
// 		end
		
// 		//divide set into two chunks, conquer
// 		Adder_Tree_Github_1 #(
// 			.DATA_WIDTH(DATA_WIDTH),
// 			.LENGTH(LENGTH_A)
// 		) subtree_a (
// 			.in_addends(addends_a),
// 			.out_sum(sum_a)
// 		);
		
// 		Adder_Tree_Github_1 #(
// 			.DATA_WIDTH(DATA_WIDTH),
// 			.LENGTH(LENGTH_B)
// 		) subtree_b (
// 			.in_addends(addends_b),
// 			.out_sum(sum_b)
// 		);
		
// 		assign out_sum = sum_a + sum_b;
// 	end
// endgenerate

// endmodule