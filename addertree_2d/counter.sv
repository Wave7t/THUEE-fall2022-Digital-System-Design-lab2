module Counter #(
    parameter CNT_BW = 8,
    parameter MAX = 8
) (
    input   clk,
    input   rst_n,
    input   start,
    output  [CNT_BW-1:0] cur_val,
    output  is_counting
);
    reg [CNT_BW-1:0] val;
    reg counting;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            val <= MAX;
            counting <= 0;
        end
        else if (counting) begin
            if (val == MAX-1) begin
                counting <= 0;
            end
            else begin
                counting <= 1;
            end
            val <= val + 1;
        end
        else begin
            if (start) begin
                counting <= 1;
                val <= 0;
            end
            else begin
                counting <= 0;
                val <= MAX;
            end
        end
    end

    assign is_counting = counting;
    assign cur_val = val;
    
endmodule