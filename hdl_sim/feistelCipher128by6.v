module tt_um_Samcooper01(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

//system states
localparam SYS_IDLE =       4'b0000;
localparam SYS_KEYSET =     4'b0001;
localparam SYS_STARTSET =   4'b0010;
localparam SYS_STREAMING =  4'b0011;

reg [127:0] full_key;
wire [127:0] full_key_next;
reg [7:0] feistel_out;
reg [7:0] start_seg;
wire [7:0] local_key;
reg set_key_ss, set_start_ss;
reg [3:0] curr_seg;

reg [3:0] sys_state, sys_next_state;

wire set_key, set_start, start_stream, end_stream;

reg start_count;
reg [3:0] counter;

//Sys state signals
assign set_key = (sys_state == SYS_IDLE) ? (ui_in == 8'h01) : 1'b0;
assign set_start = (sys_state == SYS_IDLE) ? (ui_in == 8'h0F) : 1'b0;
assign start_stream = (sys_state == SYS_IDLE) ? (ui_in == 8'h02) : 1'b0;
assign end_stream = (sys_state == SYS_STREAMING) ? (uio_in[1]) : 1'b0;
assign uo_out = (sys_state == SYS_STREAMING) ? feistel_out : 0;

//System state machine
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) sys_state <= 0;
    else sys_state <= sys_next_state;
end

always @(*) begin
    start_count = 0;
    set_start_ss = 0;
    set_key_ss = 0;
    
    case(sys_state)
        SYS_IDLE: begin
            if(set_key) sys_next_state = SYS_KEYSET;
            else if (set_start) sys_next_state = SYS_STARTSET;
            else if (start_stream) sys_next_state = SYS_STREAMING;
            else sys_next_state = SYS_IDLE;
        end
        SYS_KEYSET: begin
            start_count = 1;
            set_key_ss = 1;
            if(counter == 15'd15) begin
                sys_next_state = SYS_IDLE;
            end
            else sys_next_state <= SYS_KEYSET;
        end
        SYS_STARTSET: begin
            set_start_ss = 1;
            sys_next_state <= SYS_IDLE;
        end
        SYS_STREAMING: begin
            if(end_stream) begin
                sys_next_state <= SYS_IDLE;
            end
            else sys_next_state <= SYS_STREAMING;
        end
    endcase

end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        counter <= 0;
    end
    else if(start_count == 1) begin
        counter <= counter + 1'b1;
    end
    else begin
        counter <= 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        start_seg <= 0;
    end
    else if (set_start_ss) begin
        start_seg <= ui_in;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        full_key <= 0;
    end 
    else if (set_key_ss) begin
        full_key <= full_key_next;
    end
end

// Single assign: replace selected 8-bit slice with ui_in based on counter (0..15 maps to [127:120]..[7:0])
assign full_key_next = (full_key & ~(128'hFF << (8*(4'd15 - counter)))) |
                       ({{120{1'b0}}, ui_in} << (8*(4'd15 - counter)));

//Key Generator
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        curr_seg <= 0;
    end 
    else if (sys_state == SYS_STARTSET) begin
        curr_seg <= ui_in;
    end
    else if (sys_state == SYS_STREAMING) begin
        curr_seg <= curr_seg + 1;
    end
end

// Combinational: zero when reset or not streaming; otherwise select slice
assign local_key = (rst_n && (sys_state == SYS_STREAMING))
                 ? ((full_key >> (8*(4'd15 - curr_seg))) & 8'hFF)
                 : 8'h00;




// Decrypt mode control: 0=encrypt, 1=decrypt (latched when not streaming)
reg mode_dec;
always @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    mode_dec <= 1'b0;
  end else if (sys_state != SYS_STREAMING) begin
    mode_dec <= uio_in[0];
  end
end

//6 Round Cipher: data from ui_in, subkey from local_key
reg [3:0] L, R, K, F, idx;
integer i;
always @(*) begin
  // Use incoming byte as data only while streaming; otherwise zero
  // Start index and key nibble remain as before
  // Note: If 0x03 can appear in data, it will also trigger end_stream per current FSM design.
  //       Keeping behavior as-is per request.
  L = (sys_state == SYS_STREAMING) ? ui_in[7:4] : 4'h0;
  R = (sys_state == SYS_STREAMING) ? ui_in[3:0] : 4'h0;
  if (!mode_dec) begin
    // Encrypt: r=0..5, F on R
    for (i = 0; i < 6; i = i + 1) begin
      K = (start_seg[3:0] + i[3:0]) ^ local_key[7:4];
      F = ((R + K) ^ {R[2:0], R[3]});
      {L, R} = {R, (L ^ F)};
    end
  end else begin
    // Decrypt: r=5..0, F on L
    // Use forward loop with reversed per-round index to mirror C exactly
    for (i = 0; i < 6; i = i + 1) begin
      idx = (4'd5 - i[3:0]);
      K = (start_seg[3:0] + idx) ^ local_key[7:4];
      F = ((L + K) ^ {L[2:0], L[3]});
      {L, R} = {(R ^ F), L};
    end
  end
  feistel_out = {L, R};
end

endmodule;