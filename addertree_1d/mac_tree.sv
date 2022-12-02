// `include "Adder_Tree.sv"
`define CLIP_MODULE clip_v1
`define PIPELINE_TREE

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

module MAC_Tree #(
    parameter N_LAYER = 3,
    parameter IA_BW = 8,
    parameter WT_BW = 8,
    parameter ACC_BW = 32
) (
    input clk,
    input rst_n,

    // input and control signals
    input pe_enable,
    input clear_acc,
    input signed [IA_BW-1:0]      IA[2**N_LAYER-1:0],
    input signed [WT_BW-1:0]      WT[2**N_LAYER-1:0],

    // 尽管要求了是8，还是保留接�?
    input [7:0]            bit_shift,

    output signed [IA_BW-1:0]    accumu_result,
    output signed [WT_BW+N_LAYER-1:0] adder_result
);

/* 
Implements a line of MAC, with a single adder tree.
Two-stage process: multiply and sum, in 2 clock cycles.
Spatial-K optimization
Output stationary dataflow
- if pe_enable if off, this iteration does nothing
- if clear_acc is on, this iteration clears 
*/

    // input buffer --> pipeline buffer --> addertree out buffer --> accumulator

    localparam PIPELINE_BUF_1_BW    = IA_BW + WT_BW;
    localparam N_INPUT              = 2**N_LAYER;
    localparam ADDERTERR_OUT_BW     = PIPELINE_BUF_1_BW + N_LAYER;

    // Input Buffer of Data
    reg signed [IA_BW-1:0] IA_buffer [N_INPUT-1:0];
    reg signed [IA_BW-1:0] WT_buffer [N_INPUT-1:0];
    // Input Buffer of Control Signals
    reg pe_enable_buf_0;
    reg clear_acc_buf_0;

    // Pipeline buffer between MUL and Adder Tree
    reg signed [PIPELINE_BUF_1_BW-1:0] pipeline_buffer [N_INPUT-1:0];
    reg signed [ADDERTERR_OUT_BW-1:0]  addertree_out_buf;
    reg pe_enable_buf_1;
    reg clear_acc_buf_1;

    reg signed [ACC_BW-1:0] accumulator;
    reg pe_enable_buf_2;
    reg clear_acc_buf_2;

    // adder tree
    wire signed [ADDERTERR_OUT_BW-1:0] addertree_out;
    
`ifdef PIPELINE_TREE
    Adder_Tree_Pipeline #(
        PIPELINE_BUF_1_BW, N_LAYER, N_INPUT, ADDERTERR_OUT_BW
    ) addertree (
        .clk(clk),
        .rst_n(rst_n),
        .operands(pipeline_buffer), 
        .result(addertree_out)
    );
    localparam data_latency = 5;
`else // PIPELINE_TREE
    Adder_Tree #(
        PIPELINE_BUF_1_BW, N_LAYER, N_INPUT, ADDERTERR_OUT_BW
    ) addertree (
        .operands(pipeline_buffer), 
        .result(addertree_out)
    );
    localparam data_latency = 4
`endif // PIPELINE_TREE

    // output of the accumulation adder, used in different cases in different configurations
    wire signed [ACC_BW-1:0] accumulator_in = addertree_out_buf + accumulator;

    // output buffering
    reg signed [IA_BW-1:0] OA_buffer;
    
    localparam ctrl_buf_stage = data_latency - 1;
    reg [ctrl_buf_stage-1:0] pe_enable_buf;
    reg [ctrl_buf_stage-1:0] clear_acc_buf;
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pe_enable_buf <= 0;
            clear_acc_buf <= 0;
        end
        else begin 
            pe_enable_buf <= {pe_enable_buf[ctrl_buf_stage-2:0], pe_enable};
            clear_acc_buf <= {clear_acc_buf[ctrl_buf_stage-2:0], clear_acc};
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (integer n = 0; n < N_INPUT; n = n + 1) begin
                IA_buffer[n] <= 0;
                WT_buffer[n] <= 0;
                pipeline_buffer[n] <= 0;
            end
            addertree_out_buf <= 0;
            accumulator <= 0;
        end
        else begin
            // stage 1: buffer all input signals
            for (integer n = 0; n < N_INPUT; n = n + 1) begin
                IA_buffer[n] <= IA[n];
                WT_buffer[n] <= WT[n];
            end

            // stage 2: calculate the multiplication results and buffer all control signals
            for (integer n = 0; n < N_INPUT; n = n + 1)
                pipeline_buffer[n] <= IA_buffer[n] * WT_buffer[n];

            // stage 3: calculate the sum and buffer all control signals
            addertree_out_buf <= addertree_out;

            // stage 4: accumulate 
            if (~pe_enable_buf[ctrl_buf_stage-1]) begin
                accumulator <= accumulator;
            end
            else if (clear_acc_buf[ctrl_buf_stage-1]) begin
                accumulator <= 0;
            end
            else begin
                accumulator <= accumulator_in;
            end
        end
    end

    assign adder_result = addertree_out;
    clip_v1 #(ACC_BW, IA_BW) clip (accumulator >>> bit_shift, accumu_result);

endmodule