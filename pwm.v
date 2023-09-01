module pwm(clk, pwm_in, pwm_out);
input clk;
input pwm_in;
output pwm_out;

wire rxd_data_ready;
wire [7:0] rxd_data;
async_receiver uut(.clk(clk), .rxd(pwm_in), .rxd_data_ready(rxd_data_ready), .rxd_data(rxd_data));

reg [7:0] rxd_data_reg;
always @(posedge clk) begin
    if(rxd_data_ready)
        rxd_data_reg <= rxd_data;
end

reg [8:0] pwm_accumulator;
always @(posedge clk) begin
    pwm_accumulator <= pwm_accumulator[7:0] + rxd_data_reg;
end

assign pwm_out = pwm_accumulator[8];

endmodule