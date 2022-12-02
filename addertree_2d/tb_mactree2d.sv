`timescale 1ns/1ps


module tb_mactree_2d;

parameter IA_H = 100;
parameter IA_W = 150;
parameter WT_H = 150;
parameter WT_W = 16; 
parameter OA_H = 100;
parameter OA_W = 16;

parameter IA_BW = 8;
parameter WT_BW = 8;
parameter ACCU_BW = 24;

parameter N_LAYER = 4;
parameter K0 = 2**N_LAYER; // 16
parameter N0 = 8;
parameter M0 = 20;

parameter K1 = 10; //�?次�?�入15�?
parameter M1 = IA_H / M0;
parameter N1 = WT_W / N0;

// memory
reg signed [IA_BW-1:0] IA_MEM   [IA_H-1:0][IA_W-1:0];
reg signed [WT_BW-1:0] WT_MEM   [WT_H-1:0][WT_W-1:0];
reg signed [IA_BW-1:0] OA_MEM   [OA_H-1:0][OA_W-1:0];
reg signed [IA_BW-1:0] REF_OUT  [OA_H-1:0][OA_W-1:0];

// interface
reg   clk;
reg   rst_n;
reg   [WT_BW-1:0] WT_IN   [2**N_LAYER-1:0];
reg   [IA_BW-1:0] IA_IN   [2**N_LAYER-1:0];
wire  [IA_BW-1:0] OA_OUT  [N0-1:0];
reg   weight_update_start;
wire  outputing;
reg   calc_start;
reg   calc_start_resume;

mactree_2d #(
    IA_BW, WT_BW, ACCU_BW,
    M0, N0, N_LAYER
) mt (
    .clk (clk),
    .rst_n (rst_n),
    .WT_IN(WT_IN),
    .weight_update_start(weight_update_start),
    .IA_IN(IA_IN),
    .calc_start(calc_start),
    .calc_start_resume(calc_start_resume),
    .OA_OUT(OA_OUT),
    .outputing(outputing)
);

localparam CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk=~clk;

// initial begin
//     $dumpfile("tb_mactree_2d.vcd");
//     $dumpvars(0, tb_mactree_2d);
// end

integer wupdate_k1, wupdate_n1;
integer loc_k1;
integer loc_n1;
always @(posedge weight_update_start) begin
    @(negedge clk);
    weight_update_start = 0;
end
always @(posedge weight_update_start) begin
    loc_k1 = wupdate_k1;
    loc_n1 = wupdate_n1;
    for (integer nwu = 0; nwu < N0; nwu = nwu + 1) begin
        @(negedge clk);
        for (integer wcnt = 0; wcnt < 15; wcnt = wcnt + 1) begin
            WT_IN[wcnt] <= WT_MEM[loc_k1 * 15 + wcnt][loc_n1 * N0 + nwu];
        end
        WT_IN[15] <= 0;
    end
end

always @(posedge calc_start) begin
    @(negedge clk);
    calc_start = 0;
end

integer wb_m1, wb_n1;
integer wbm1_loc, wbn1_loc;

// reg en_wb_g = 0;
// reg outputing_prev = 0;
// always @(posedge clk) begin
//     outputing_prev <= outputing;
//     if (~outputing_prev && outputing && en_wb_g) begin
//         wbm1_loc = wb_m1;
//         wbn1_loc = wb_n1;
//         en_wb_g = 0;
//         for (integer wbm = wbm1_loc * M0; wbm < (wbm1_loc + 1) * M0; wbm = wbm + 1) begin
//             for (integer n = 0; n < N0; n = n + 1)
//                 OA_MEM[wb_m][wbn1_loc * N0 + n] <= OA_OUT[n];
//             @(negedge clk);
//         end
//     end
// end

reg set_wb = 0;
integer wb_m;
always @(posedge set_wb) begin
    wbm1_loc = wb_m1;
    wbn1_loc = wb_n1;
    wb_m = wbm1_loc * M0;
    set_wb = 0;
end
always @(posedge clk) begin
    if (outputing) begin
        for (integer n = 0; n < N0; n = n + 1)
            OA_MEM[wb_m][wb_n1 * N0 + n] <= OA_OUT[n];
        wb_m <= wb_m + 1;
    end
end

integer wrong_num = 0;

initial begin
    $readmemb("input_act_bin.txt", IA_MEM);
    $readmemb("weight_bin_t.txt", WT_MEM);
    $readmemb("reference_output_bin.txt", REF_OUT);

    clk = 0;
    rst_n = 0;
    wupdate_k1 = 0;
    wupdate_n1 = 0;
    weight_update_start = 0;
    calc_start = 0;
    calc_start_resume = 0;
    @(negedge clk) rst_n = 1;

    @(negedge clk);
    // 第一步：加载�?要的weight
    weight_update_start = 1;
    repeat(10) @(negedge clk);
    // 应该加载完了
    // $finish;

    for (integer n1 = 0; n1 < N1; n1 = n1 + 1) begin
        for (integer m1 = 0; m1 < M1; m1 = m1 + 1) begin
            for (integer k1 = 0; k1 < K1; k1 = k1 + 1) begin
                // load weight for the next iter
                wupdate_k1 = (k1 + 1) % K1;
                wupdate_n1 = ((k1 == K1 - 1) && (m1 == M1 - 1)) ? (n1 + 1) % N1 : n1;
                weight_update_start = 1;

                // �?始一轮的计算
                calc_start = 1;
                calc_start_resume = (k1 != 0);

                for(integer m0 = 0; m0 < M0; m0 = m0 + 1) begin
                    @(negedge clk);
                    for (integer k0 = 0; k0 < 15; k0 = k0 + 1) begin
                        IA_IN[k0] <= IA_MEM[m1 * M0 + m0][k1 * 15 + k0];
                    end
                    IA_IN[15] <= 0;
                end
                repeat(1) @(negedge clk);
            end
            // 到这个时候差不多就该write back了�??
            wb_m1 = m1;
            wb_n1 = n1;
            set_wb = 1;
        end
    end
    calc_start = 1;
    calc_start_resume = 0;
    repeat(22) @(negedge clk);

    for (integer m = 0; m < OA_H; m = m + 1) begin
        for (integer n = 0; n < OA_W; n = n + 1) begin
            if (OA_MEM[m][n] != REF_OUT[m][n]) begin
                $display("(%d,%d): output %d, reference %d", m,n,OA_MEM[m][n], REF_OUT[m][n]);
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

endmodule