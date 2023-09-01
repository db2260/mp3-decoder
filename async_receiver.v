// RX: 8 bit data, 1 stop, no parity (the receiver can accept more stop bits)

module async_receiver (clk, rxd, rxd_data_ready, rxd_data, rxd_idle, rxd_endofpacket);
input clk;
input rxd;
output reg rxd_data_ready = 0;
output reg [7:0] rxd_data = 0;  //data received, valid for one clock cycle when rxd_data_ready is asserted
 
//we can also detect if a gap occurs in the received stream of characters
//this is useful if multiple characters are sent in a burst
//multiple characters can be treated as a "packet"
output rxd_idle;
output reg rxd_endofpacket = 0;

parameter clk_freq = 25000000; //25MHz
parameter baud = 115200;

//needs to be a power of 2
//oversample the rxd line at a fixed rate to capture each rxd data bit at the "right" time
//8 times oversampling by default, use 16 for higher quality reception
parameter over_sampling = 8; 

reg [3:0] rxd_state = 0;

`ifdef SIMULATION
wire rxd_bit = rxd;
wire sample_now = 1'b1;

`else
wire over_sampling_tick;
baud_tick_gen #(clk_freq, baud, over_sampling) tickgen(.clk(clk), .enable(1'b1), .tick(over_sampling_tick));

//synchronize rxd to our clock domain
reg [1:0] rxd_sync = 2'b11;
always @(posedge clk) begin
    if(over_sampling_tick)
        rxd_sync <= {rxd_sync[0], rxd};
end

//and filter it
reg [1:0] filter_cnt = 2'b11;
reg rxd_bit = 1'b1;

always @(posedge clk) begin
    if(over_sampling_tick) begin
        if(rxd_sync[1] == 1'b1 && filter_cnt != 2'b11)
            filter_cnt <= filter_cnt + 1'd1;
        else begin
            if(rxd_sync[1] == 1'b0 && filter_cnt != 2'b00)
                filter_cnt <= filter_cnt - 1'd1;
            if(filter_cnt == 2'b11)
                rxd_bit <= 1'b1;
            else
                if(filter_cnt == 2'b00)
                    rxd_bit <= 1'b0;
        end
    end
end

//and decide when it is time to sample the rxd line
function integer log2(input integer v); begin 
    log2=0; 
    while(v>>log2)
        log2=log2+1;
end
endfunction

localparam p = log2(over_sampling);
reg [p-2:0] over_sampling_cnt = 0;

always @(posedge clk) begin
    if(over_sampling_tick)
        over_sampling_cnt <= (rxd_state==0) ? 1'd0 : over_sampling_cnt + 1'd1;
end

wire sample_now = over_sampling_tick && (over_sampling_cnt == over_sampling/2-1);
`endif

//now we can accumulate the rxd bits in a shift register
always @(posedge clk) begin
    case(rxd_state)
        4'b0000: if(~rxd_bit) rxd_state <= `ifdef SIMULATION 4'b1000 `else 4'b0001 `endif;  //start bit found?
        4'b0001: if(sample_now) rxd_state <= 4'b1000;   //sync start bit to sample_now
        4'b1000: if(sample_now) rxd_state <= 4'b1001;   //bit 0
        4'b1001: if(sample_now) rxd_state <= 4'b1010;   //bit 1
        4'b1010: if(sample_now) rxd_state <= 4'b1011;   //bit 2
        4'b1011: if(sample_now) rxd_state <= 4'b1100;   //bit 3
        4'b1100: if(sample_now) rxd_state <= 4'b1101;   //bit 4
        4'b1101: if(sample_now) rxd_state <= 4'b1110;   //bit 5
        4'b1110: if(sample_now) rxd_state <= 4'b1111;   //bit 6
        4'b1111: if(sample_now) rxd_state <= 4'b0010;   //bit 7
        4'b0010: if(sample_now) rxd_state <= 4'b0000;   //bit 8
        default: rxd_state <= 4'b0000;
    endcase
end

always @(posedge clk) begin
    if(sample_now && rxd_state[3])
        rxd_data <= {rxd_bit, rxd_data[7:1]};
end

//reg rxd_data_error = 0;
always @(posedge clk) begin
    rxd_data_ready <= (sample_now && rxd_state==4'b0010 && rxd_bit);    //make sure a stop bit is received
    //rxd_data_error <= (sample_now && rxd_state==4'b0010 && ~rxd_bit); //error if a stop bit is not received
end

`ifdef SIMULATION
assign rxd_idle = 0;
`else
reg [p+1:0] gap_cnt = 0;

always @(posedge clk) begin
    if(rxd_state != 0)
        gap_cnt <= 0;
    else
        if(over_sampling_tick && ~gap_cnt[log2(over_sampling)+1])
            gap_cnt <= gap_cnt + 1'h1;
end

assign rxd_idle = gap_cnt[p+1];

always @(posedge clk) begin
    rxd_endofpacket <= over_sampling_tick & ~gap_cnt[p+1] & &gap[p:0];
end

`endif


endmodule


module baud_tick_gen (clk, enable, tick);
input clk, enable;
output tick;    //generate a tick at the specified baud rate * over_sampling

parameter clk_freq = 25000000;
parameter baud = 115200;
parameter over_sampling = 1;

function integer log2(input integer v); begin 
    log2=0; 
    while(v>>log2)
        log2=log2+1;
end
endfunction

localparam acc_width = log2(clk_freq/baud) + 8;
reg [acc_width:0] acc = 0;
localparam shift_limiter = log2(baud*over_sampling >> (31-acc_width));  //this makes sure inc calculation does not overflow
localparam inc = ((baud*over_sampling << (acc_width-shift_limiter)) + ( clk_freq >> (shift_limiter+1))) / (clk_freq >> shift_limiter);

always @(posedge clk) begin
    if(enable)
        acc <= acc[acc_width-1:0] + inc[acc_width:0];
    else
        acc <= inc[acc_width:0];
end

assign tick = acc[acc_width];

endmodule
