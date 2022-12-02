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