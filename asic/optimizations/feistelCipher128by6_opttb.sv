module feistelCipher128by6_tb();

logic clk, rst_n;

// Inputs we drive are logic; DUT outputs are wires we do not drive
logic [7:0] ui_in, uio_in;
wire  [7:0] uo_out, uio_out, uio_oe;

bit in_stream;
bit stopping;
bit curr_mode_dec;
reg [1:0] stop_window;

byte key_mem   [0:15];
byte data_mem  [0:4095];
int  key_fd, data_fd, out_fd;
int  key_n, data_n;

// Buffers for self-check
byte pt_bytes   [0:4095];
byte ct_bytes   [0:4095];
byte rt_bytes   [0:4095];
int  pt_n;
int mismatches = 0;
byte tmp_idx;

string key_path;
string pt_path;
string ct_out_path;
string rt_out_path;
byte   start_idx_var;

// Defaults (can be overridden via plusargs in the future)
localparam string KEY_PATH              = {KEYS_DIR, "\\.privatekey0"};
localparam string PLAINTEXT_PATH        = {PLAINTEXT_DIR, "\\plaintext0.txt"};
localparam string CIPHERTEXT_OUT_PATH   = {CIPHERTEXT_DIR, "\\ciphertext0.bin"};
localparam string ROUNDTRIP_OUT_PATH    = {ROUNDTRIP_DIR,  "\\roundtrip0.bin"};
localparam byte   START_IDX             = 8'h08;
localparam string KEYS_DIR        = "C:\\Users\\Sam\\Desktop\\FeistelCIpher-Silicon\\128bitFeistelCipher\\hdl_sim\\tests\\keys";
localparam string PLAINTEXT_DIR   = "C:\\Users\\Sam\\Desktop\\FeistelCIpher-Silicon\\128bitFeistelCipher\\hdl_sim\\tests\\plaintext";
localparam string CIPHERTEXT_DIR  = "C:\\Users\\Sam\\Desktop\\FeistelCIpher-Silicon\\128bitFeistelCipher\\hdl_sim\\tests\\ciphertext";
localparam string ROUNDTRIP_DIR   = "C:\\Users\\Sam\\Desktop\\FeistelCIpher-Silicon\\128bitFeistelCipher\\hdl_sim\\tests\\roundtrip";

tt_um_Samcooper01_opt iDUT(
    .ui_in(ui_in),  
    .uo_out(uo_out),  
    .uio_in(uio_in),  
    .uio_out(uio_out),  
    .uio_oe(uio_oe),   
    .ena(1'b1),      
    .clk(clk),   
    .rst_n(rst_n)   
);

task automatic load_key_16(input string path);
    int fd; int r;
    fd = $fopen(path, "rb");
    if (fd == 0) $fatal(1, "Failed to open key file: %s", path);
    r = $fread(key_mem, fd);
    $fclose(fd);
    if (r < 16) $fatal(1, "Key file must be at least 16 bytes, got %0d", r);
endtask

task automatic tb_dump_bytes_to_bits_file(
    input string out_path,
    input byte   data_buf [0:4095],
    input int    n
);
    int fd;
    begin
        fd = $fopen(out_path, "wb");
        if (fd == 0) $fatal(1, "Failed to open output file: %s", out_path);
        for (int i = 0; i < n; i++) begin
            for (int b = 7; b >= 0; b--) begin
                void'($fwrite(fd, "%c", ((data_buf[i] >> b) & 1) ? 8'h31 : 8'h30));
            end
        end
        $fclose(fd);
    end
endtask

task automatic load_data_bytes(input string path);
    int fd; int r;
    fd = $fopen(path, "rb");
    if (fd == 0) $fatal(1, "Failed to open plaintext file: %s", path);
    r = $fread(data_mem, fd);
    $fclose(fd);
    if (r <= 0) $fatal(1, "No data read from plaintext file: %s", path);
    data_n = r;
endtask


task automatic load_bits_as_bytes(input string path);
    int fd; int ch; int bit_cnt; byte curr;
    fd = $fopen(path, "rb");
    if (fd == 0) $fatal(1, "Failed to open bits file: %s", path);
    data_n = 0;
    bit_cnt = 0;
    curr = 8'h00;
    while (!$feof(fd)) begin
        ch = $fgetc(fd);
        if (ch == 8'h30 || ch == 8'h31) begin 
            curr = {curr[6:0], (ch == 8'h31)}; 
            bit_cnt++;
            if (bit_cnt == 8) begin
                data_mem[data_n] = curr;
                data_n++;
                bit_cnt = 0;
                curr = 8'h00;
            end
        end
    end
    $fclose(fd);
endtask

task automatic tb_reset();
    begin
        rst_n = 0;
        uio_in = 0;
        ui_in  = 0;
        @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    end
endtask

task automatic tb_set_key();
    begin
        int key_load_count;
        key_load_count = 0;
        ui_in = 8'h01;
        @(posedge clk);
        for (int i = 0; i < 16; i++) begin
            ui_in = key_mem[i];
            @(posedge clk);
            key_load_count++;
        end
        ui_in = 8'h00;
        repeat (5) @(posedge clk);
        assert (key_load_count == 16) else $error("key load count != 16, got %0d", key_load_count);
    end
endtask

task automatic tb_set_start_idx(input byte idx);
    begin
        ui_in = 8'h0F; 
        @(posedge clk);
        ui_in = idx;   
        @(posedge clk);
        repeat (5) @(posedge clk);
    end
endtask

task automatic tb_start_stream();
    begin
        ui_in = 8'h02;
        @(posedge clk);
        in_stream = 1'b1;
    end
endtask

task automatic tb_stop_stream();
    begin
        stopping = 1'b1;
        uio_in[1] = 1'b1; 
        @(posedge clk);
        uio_in[1] = 1'b0;
        in_stream = 1'b0;
        stopping = 1'b0;
    end
endtask

task automatic tb_stream_current_data_to_file(input string out_path);
    int fd;
    begin
        fd = $fopen(out_path, "wb");
        if (fd == 0) $fatal(1, "Failed to open output file: %s", out_path);
        for (int i = 0; i < data_n; i++) begin
            ui_in = data_mem[i];
            @(posedge clk);
            for (int b = 7; b >= 0; b--) begin
                void'($fwrite(fd, "%c", (uo_out[b] ? 8'h31 : 8'h30)));
            end
        end
        $fclose(fd);
    end
endtask

task automatic tb_stream_bytes(
    input  byte in_mem   [0:4095],
    input  int  n,
    output byte out_mem  [0:4095]
);
    begin
        if (n > 0) begin
            // Prime the 1-cycle output pipeline: drive first byte, do not capture yet
            ui_in = in_mem[0];
            @(posedge clk);
            // Stream remaining bytes, capturing previous cycle's output
            for (int i = 1; i < n; i++) begin
                ui_in = in_mem[i];
                @(posedge clk);
                out_mem[i-1] = uo_out;
            end
            // Drain: capture the last pipelined output
            @(posedge clk);
            out_mem[n-1] = uo_out;
        end
    end
endtask

task automatic tb_run_pass(
    input  bit  decrypt,
    input  byte in_mem   [0:4095],
    input  int  n,
    input  byte start_idx,
    output byte out_mem  [0:4095]
);
    begin
        tb_set_start_idx(start_idx);
        // set mode
        uio_in[0] = decrypt; 
        curr_mode_dec = decrypt;
        @(posedge clk);
        tb_start_stream();
        // Allow one extra cycle for DUT output valid pipeline to prime
        @(posedge clk);
        tb_stream_bytes(in_mem, n, out_mem);
        tb_stop_stream();
        uio_in[0] = 1'b0; 
    end
endtask

task automatic tb_compare_buffers(
    input  byte exp_mem [0:4095],
    input  byte got_mem [0:4095],
    input  int  n,
    output int  mismatch_count
);
    begin
        mismatch_count = 0;
        for (int i = 0; i < n; i++) begin
            if (got_mem[i] !== exp_mem[i]) begin
                $error("Roundtrip mismatch at byte %0d: got %02x expected %02x", i, got_mem[i], exp_mem[i]);
                mismatch_count++;
            end
        end
    end
endtask

task automatic tb_encrypt(
    input string key_path,
    input string plaintext_path,
    input byte   start_idx
);
    begin
        tb_reset();
        load_key_16(key_path);
        load_data_bytes(plaintext_path);
        pt_n = data_n;
        for (int i = 0; i < pt_n; i++) pt_bytes[i] = data_mem[i];
        tb_set_key();
        tb_run_pass(1'b0, pt_bytes, pt_n, start_idx, ct_bytes);
    end
endtask

task automatic tb_decrypt(
    input byte start_idx
);
    begin
        tb_reset();
        tb_set_key();
        tb_run_pass(1'b1, ct_bytes, pt_n, start_idx, rt_bytes);
    end
endtask

initial begin
    clk = 0; 
    rst_n = 0;
    ui_in = 0;
    uio_in = 0;
    @(posedge clk);

    key_path     = KEY_PATH;
    pt_path      = PLAINTEXT_PATH;
    ct_out_path  = CIPHERTEXT_OUT_PATH;
    rt_out_path  = ROUNDTRIP_OUT_PATH;
    start_idx_var = START_IDX;

    // Optional overrides via plusargs
    void'($value$plusargs("KEY=%s",  key_path));
    void'($value$plusargs("PT=%s",   pt_path));
    void'($value$plusargs("CT=%s",   ct_out_path));
    void'($value$plusargs("RT=%s",   rt_out_path));
    if ($value$plusargs("START=%h", tmp_idx)) start_idx_var = tmp_idx;

    // Single-case run
    tb_encrypt(key_path, pt_path, start_idx_var);
    tb_dump_bytes_to_bits_file(ct_out_path, ct_bytes, pt_n);
    tb_decrypt(start_idx_var);
    tb_dump_bytes_to_bits_file(rt_out_path, rt_bytes, pt_n);

    // Self-check
    tb_compare_buffers(pt_bytes, rt_bytes, pt_n, mismatches);
    if (mismatches) $fatal(1, "Self-check FAILED: %0d mismatches", mismatches);
    else $display("Self-check PASSED: %0d bytes matched", pt_n);

    #50;
    $stop();
end

// Assertions
always @(posedge clk) begin
    if (rst_n) begin
        if (in_stream) begin
            assert (uio_in[0] == curr_mode_dec) else $error("mode changed during stream");
            if (!stopping) begin
                assert (uio_in[1] == 1'b0) else $error("stop asserted unexpectedly during stream");
            end
            // Only check for unknowns while streaming to avoid idle X noise
            assert (!$isunknown(uo_out)) else $error("unknown on DUT uo_out during stream");
        end
        else if (stop_window == 2'd0) begin
            // When fully idle (and not within the post-stop grace window), output must be 0 and known
            assert (!$isunknown(uo_out)) else $error("unknown on DUT uo_out when idle");
            assert (uo_out == 8'h00) else $error("uo_out not zero when idle");
        end
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        stop_window <= 2'd0;
    end else begin
        // On stop request, open a 2-cycle window; after that, require uo_out low
        if (stopping)
            stop_window <= 2'd2;
        else if (stop_window != 0)
            stop_window <= stop_window - 1'b1;

        // Rely on idle-zero assertion once stop_window elapses
    end
end

always begin
    #5 clk <= ~clk;
end 

endmodule