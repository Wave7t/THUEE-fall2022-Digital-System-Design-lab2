`timescale 1ns/1ps

// `include "Systolic_Array_OA_reg.sv"
`include "Systolic_Array_2.sv"

module tb_Systolic_Array_2;

// interface
parameter N = 10;
// 没办法，就这样
parameter M0 = N-1;
parameter IA_BW = 8;
parameter WT_BW = 8;
parameter ACC_BW = 32;
parameter MM_BW = (IA_BW < WT_BW) ? WT_BW : IA_BW;

reg clk;
reg rst_n;
reg reset_weight;
reg specified_accum_in;

// reg signed [ACC_BW-1:0] accum_in;
wire signed [ACC_BW-1:0] out;

reg signed [IA_BW-1:0] IA [N-1:0];
reg signed [WT_BW-1:0] WT [N-1:0];

reg signed [MM_BW-1:0] IN [N-1:0];


// 简化的设计：只需要把数据塞入IA和WT，然后改reset_weight，输入自动设置好
always @(*) begin
    if (~reset_weight) begin
        for (integer e = 0; e < N; e = e + 1) begin
            IN[e][IA_BW-1:0] <= IA[e];
            if (MM_BW > IA_BW) IN[e][MM_BW-1:IA_BW] <= 0;
        end
    end
    else begin
        for (integer e = 0; e < N; e = e + 1) begin
            IN[e][WT_BW-1:0] <= WT[e];
            if (MM_BW > WT_BW) IN[e][MM_BW-1:WT_BW] <= 0;
        end
    end
end

Systolic_Array_1D_v2 #(
    N, IA_BW, WT_BW, MM_BW, ACC_BW
) ssa (
    .clk(clk),
    .rst_n(rst_n),
    .reset_weight(reset_weight),
    .IN(IN),
    .specified_accum_in(specified_accum_in),
    // .accum_in(accum_in),
    .accum_in(out),
    .out(out)
);

wire signed [7:0] result;

clip_v1 #(
    ACC_BW, 8
) c (
    .data_in(out >>> 8),
    .data_out(result)
);
// Systolic_Array_OA_reg #(
//     ACC_BW, M0
// ) ssaoar (
//     .clk(clk),
//     .rst_n(rst_n),
//     .Seq_IN(out),
//     .Seq_OUT(accum_in)
// )
// delayer #(
//     ACC_BW, M0
// ) d (
//     .clk(clk),
//     .rst_n(rst_n),
//     .data_in(out),
//     .data_out(accum_in)
// );


// memory
parameter IA_H = 100;
parameter IA_W = 150;
parameter WT_H = 150;
parameter WT_W = 16; 
parameter OA_H = 100;
parameter OA_W = 16;

// looping constants
integer K0_res = WT_H % N;
integer K1 = (K0_res == 0) ? (WT_H / N) : (WT_H / N + 1);
integer M0_res = IA_H % M0;
integer M1 = (M0_res == 0) ? (IA_H / M0) : (IA_H / M0 + 1);

reg signed [IA_BW-1:0] IA_MEM   [IA_H-1:0][IA_W-1:0];
reg signed [WT_BW-1:0] WT_MEM   [WT_H-1:0][WT_W-1:0];
reg signed [IA_BW-1:0] OA_MEM   [OA_H-1:0][OA_W-1:0];
reg signed [IA_BW-1:0] REF_OUT  [OA_H-1:0][OA_W-1:0];

// zero padder
// 对m的两层循环都是时序的，因此需要的其实是每次构造出一个内层循环规模M0
// 只要设置m1_value，就可以用M0_for_loop循环了
// M0_for_loop直接送给delayer
integer m1_value;
integer M0_for_loop = 0;
always @(*) begin
    if (m1_value == M1-1 && M0_res != 0) M0_for_loop <= M0_res;
    else M0_for_loop <= M0;
end


integer WIA_k1 = 0, W_n = 0, IA_m = 0;
// 需要加载IA就直接设置WIA_k1和IA_m；数据就过去了。
// 需要加载WT就直接设置WIA_k1和W_n
// IA_m的设置：还需要
integer k_start = 0, k_end = N;
always @(*) begin
    k_start = WIA_k1 * N;
    k_end = k_start + N;
    if (k_end > IA_W) begin
        for (integer cnt = 0; cnt < IA_W - k_start; cnt = cnt + 1) begin
            IA[cnt] <= IA_MEM[IA_m][cnt + k_start];
            WT[cnt] <= WT_MEM[cnt + k_start][W_n];
        end
        for (integer cnt = IA_W - k_start; cnt < N; cnt = cnt + 1) begin 
            IA[cnt] <= 0;
            WT[cnt] <= 0;
        end
    end
    else begin
        for (integer cnt = 0; cnt < N; cnt = cnt + 1) begin
            IA[cnt] <= IA_MEM[IA_m][cnt + k_start];
            WT[cnt] <= WT_MEM[cnt + k_start][W_n];
        end
    end
end


// counter back
reg counting;
integer M0_for_loop_counting;
integer n_counting;
integer m1_counting;
integer counting_base;
integer n_counting_rep;
always @(posedge counting) begin
    counting_base = m1_counting * M0;
    n_counting_rep = n_counting;
    @(negedge clk) 
    @(negedge clk) 
    for (integer counter = 0; counter < M0_for_loop_counting; counter = counter + 1) begin
        @(negedge clk)
        OA_MEM[counting_base + counter][n_counting_rep] = result;
        $display("out[%d,%d]: %d", counting_base + counter, n_counting_rep, out);
    end
    counting = 0;
end

// clk
localparam CLK_PERIOD = 10/2.63;
always #(CLK_PERIOD/2) clk=~clk;

initial begin
    $dumpfile("tb_Systolic_Array_2.vcd");
    $dumpvars(1, tb_Systolic_Array_2);
end

always @(posedge clk) begin
    // $display("SSA.input: (%d,%d) -> %d -> %d", ssa.reset_weight, ssa.IN[0], ssa.wire_ibuf2delay[0], ssa.wire_delay2pe[0]);
    $display("out: %d, result: %d", out, result);
end

integer wrong_num = 0;
// initial begin
//     repeat (10000) begin
//         @(negedge clk)

//     end
// end

initial begin
    // initialization
    $readmemb("input_act_bin.txt", IA_MEM);
    $readmemb("weight_bin_t.txt", WT_MEM);
    $readmemb("reference_output_bin.txt", REF_OUT);

    clk = 0;
    rst_n = 1;
    reset_weight = 0;
    specified_accum_in = 0;
    counting = 0;
    for (integer n = 0; n < N; n = n + 1) begin
        IA[n] <= 0;
        WT[n] <= 0;
    end
    // accum_in <= 0;

    @(negedge clk) rst_n = 0;
    @(negedge clk) rst_n = 1;

    $display("%d, %d, %d, %d, %d, %d", M1, M0_res, M0, K1, K0_res, N);


    // =======================================================
    // data loading procedure
    @(negedge clk);
    for (integer n = 0; n < WT_W; n = n + 1) begin
        n_counting = n;
        for (integer m1 = 0; m1 < M1; m1 = m1 + 1) begin
            // get M0_for_loop ready
            m1_value = m1;
            #1
            $display("------------ NEW LOOP -----------");
            for (integer k1 = 0; k1 < K1; k1 = k1 + 1) begin
                // move in W
                @(negedge clk) 
                reset_weight = 1;
                WIA_k1 = k1;
                W_n = n;

                // $display("W: %d, loops: %d, (%d, %d)", IN[0], M0_for_loop, IN[0] == IA[0], IN[0] == WT[0]);
                // $display("WT: %p", WT);
                #1
                $write("WT: ");
                for (integer q = 0; q < N; q = q + 1) $write("%d,", IN[q]);
                $write("\n");
                $display("looping: %d", M0_for_loop);

                for (integer m0 = 0; m0 < M0_for_loop; m0 = m0 + 1) begin
                    // start to load IA
                    @(negedge clk)
                    specified_accum_in = (k1!=0);
                    reset_weight = 0;
                    IA_m = m0 + m1 * M0;
                    // $display("IA: %d, (%d, %d)", IA[0], IN[0] == IA[0], IN[0] == WT[0]);
                    // $display("IA: %p", IN);
                    #1
                    $write("m=%d IA: ", IA_m);
                    for (integer q = 0; q < N; q = q + 1) $write("%d,", IN[q]);
                    $write("\n");
                end
                if (M0 != M0_for_loop) repeat(M0 - M0_for_loop) begin
                    @(negedge clk);
                    // #1
                    // $write("[UNUSED] IA: ");
                    // for (integer q = 0; q < N; q = q + 1) $write("%d,", IN[q]);
                    // $write("\n");
                end
                #1
                M0_for_loop_counting = M0_for_loop;
                m1_counting = m1;
                // specified_accum_in = 1;
            end
            // 再一个周期(或者说，两个negedge)，就开始收集输出了
            counting = 1;
        end
    end
    repeat(N+1) @(negedge clk);
    $finish;

    // // compare
    // repeat(2 * N) @(negedge clk);
    // for (integer m = 0; m < OA_H; m = m + 1) begin
    //     for (integer n = 0; n < OA_W; n = n + 1) begin
    //         if (OA_MEM[m][n] != REF_OUT[m][n]) begin
    //             $display("(%d,%d): output %d, reference %d", m,n,OA_MEM[m][n], REF_OUT[m][n]);
    //             wrong_num = wrong_num + 1;
    //         end
    //         else begin
    //             $display("Correct: (%d,%d): output %d, reference %d", m,n,OA_MEM[m][n], REF_OUT[m][n]);
    //         end
    //     end // n
    // end // m
    // $display("Total wrong number: %d", wrong_num);
    // @(negedge clk)
    // $finish;

end

endmodule