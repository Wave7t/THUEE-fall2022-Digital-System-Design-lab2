`timescale 1ns/1ps
// `include "mac_tree.sv"

module tb_mac_tree;


// configuration params
parameter N_LAYER = 4;
parameter IA_BW = 8;
parameter WT_BW = 8;
parameter ACC_BW = 32;

parameter IA_H = 100;
parameter IA_W = 150;
parameter WT_H = 150;
parameter WT_W = 16; 
parameter OA_H = 100;
parameter OA_W = 16;

// main memory
reg signed [IA_BW-1:0] IA_MEM   [IA_H-1:0][IA_W-1:0];
// Transpose version of weight
// reg signed [WT_BW-1:0] WT_MEM_T [WT_H-1:0][WT_W-1:0];
reg signed [WT_BW-1:0] WT_MEM   [WT_W-1:0][WT_H-1:0];
reg signed [IA_BW-1:0] OA_MEM   [OA_H-1:0][OA_W-1:0];
reg signed [IA_BW-1:0] REF_OUT  [OA_H-1:0][OA_W-1:0];

// IO
reg clk;
reg rst_n;
reg pe_enable;
reg clear_acc;
reg signed [IA_BW-1:0]      IA[2**N_LAYER-1:0];
reg signed [WT_BW-1:0]      WT[2**N_LAYER-1:0];
reg [7:0]            bit_shift = 8'd8;
wire signed [IA_BW-1:0]    accumu_result;
wire signed [WT_BW+N_LAYER-1:0] adder_result;

MAC_Tree #(
    N_LAYER, IA_BW, WT_BW, ACC_BW
) mactree (
    .clk (clk),
    .rst_n (rst_n),
    .pe_enable(pe_enable),
    .clear_acc(clear_acc),
    .IA(IA),
    .WT(WT),
    .bit_shift(bit_shift),
    .accumu_result(accumu_result),
    .adder_result(adder_result)
);


localparam CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk=~clk;

// initial begin
//     $dumpfile("tb_mac_tree.vcd");
//     $dumpvars(0, tb_mac_tree);
// end
integer g_m = 0, g_n = 0;
integer count_back = 0;
integer counting = 0;
always @(negedge clk) begin
    if (counting) begin
        if (count_back != 0) count_back <= count_back - 1;
        else begin
            counting <= 0;
            OA_MEM[g_m][g_n] <= accumu_result;
        end
    end
end



integer wrong_num = 0;
initial begin
    clk = 0;
    rst_n = 0;
    pe_enable = 0;
    clear_acc = 0;
    for (integer n = 0; n < mactree.N_INPUT; n = n + 1) begin
        IA[n] <= 0;
        WT[n] <= 0;
    end

    // load data
    $readmemb("input_act_bin.txt", IA_MEM);
    $readmemb("weight_bin_t.txt", WT_MEM);
    $readmemb("reference_output_bin.txt", REF_OUT);

    // simulation begins
    @(negedge clk); rst_n <= 1;

    for (integer m = 0; m < OA_H; m = m + 1) begin
        for (integer n = 0; n < OA_W; n = n + 1) begin
            
            @(negedge clk);
            pe_enable = 1;
            clear_acc = 1;
            // check if buffer cleared 
            for (integer k1 = 0; k1 < IA_W / mactree.N_INPUT; k1 = k1 + 1) begin
                // prepare input (parallel) and wait for the result to come
                @(negedge clk);
                for (integer k0 = 0; k0 < mactree.N_INPUT; k0 = k0 + 1) begin
                    // $display("%d, %d", IA_MEM[m][k1 * mactree.N_INPUT + k0], WT_MEM[n][k1 * mactree.N_INPUT + k0]);
                    IA[k0] <= IA_MEM[m][k1 * mactree.N_INPUT + k0];
                    WT[k0] <= WT_MEM[n][k1 * mactree.N_INPUT + k0];
                end
                clear_acc <= 0;
            end
            // deal with the margin
            if (IA_W % mactree.N_INPUT != 0) begin
                @(negedge clk);
                for (integer k0 = 0; k0 < IA_W % mactree.N_INPUT; k0 = k0 + 1) begin
                    IA[k0] <= IA_MEM[m][(IA_W / mactree.N_INPUT) * mactree.N_INPUT + k0];
                    WT[k0] <= WT_MEM[n][(IA_W / mactree.N_INPUT) * mactree.N_INPUT + k0];
                end
                for (integer k0 = IA_W % mactree.N_INPUT; k0 < mactree.N_INPUT; k0 = k0 + 1) begin
                    IA[k0] <= 0;
                    WT[k0] <= 0;
                end
                clear_acc <= 0;
            end
            
            g_m = m;
            g_n = n;
            count_back = mactree.data_latency - 1;
            counting = 1;
            
//            // need to wait a few clock cycles for the results to come out
//            for (integer cnt = 0; cnt < mactree.data_latency + 1; cnt = cnt + 1) begin
//                @(negedge clk);
//                pe_enable <= 0;
//            end
//            // move the result back
//            OA_MEM[m][n] <= accumu_result;
        end // n
    end // m
    @(negedge clk)
    pe_enable = 0;
    
    for (integer m = 0; m < OA_H; m = m + 1) begin
        for (integer n = 0; n < OA_W; n = n + 1) begin
            if (OA_MEM[m][n] != REF_OUT[m][n]) begin
                // $display("(%d,%d): output %d, reference %d", m,n,OA_MEM[m][n], REF_OUT[m][n]);
                wrong_num = wrong_num + 1;
            end
            else begin
                $display("Correct: (%d,%d): output %d, reference %d", m,n,OA_MEM[m][n], REF_OUT[m][n]);
            end
        end // n
    end // m
    $display("Total wrong number: %d", wrong_num);
    $finish;
end

initial begin
end

endmodule