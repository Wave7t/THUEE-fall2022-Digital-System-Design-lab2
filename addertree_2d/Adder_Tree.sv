

module Signed_Ext #(
    parameter BITW = 8
) (
    input  [BITW-1:0] data,
    output [BITW:0]   out
);
    assign out[BITW-1:0] = data;
    assign out[BITW]     = data[BITW-1];
endmodule

// complicated, needs specialized initializer
module Adder_Tree #(
    parameter INPUT_BW = 8,
    parameter LAYER_NUM = 3,
    parameter ARRAY_SIZE = 8,
    parameter OUTPUT_BW = 11
) (
    input  signed [INPUT_BW-1:0] operands [ARRAY_SIZE-1:0],
    output signed [OUTPUT_BW-1:0] result
);

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
            assign Wires[n].outputs[m] = op1 + op2;
        end
    end
endgenerate

    assign result = Wires[LAYER_NUM-1].outputs[0];

endmodule