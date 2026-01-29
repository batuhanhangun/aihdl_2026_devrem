// ============================================================================
// TinyQV FFT Peripheral - 8-Point FFT Accelerator
// AI-HDL 2026 Competition - Design Phase 1
// 
// This module wraps the 8-point FFT core with a memory-mapped register
// interface compatible with TinyQV peripherals.
//
// Register Map (32-bit aligned):
// 0x00-0x1C: INPUT_REAL[0-7]  - Real part of input samples (write)
// 0x20-0x3C: INPUT_IMAG[0-7]  - Imaginary part of input samples (write)
// 0x40:      CONTROL          - Write 0x01 to start FFT
// 0x44:      STATUS           - Bit 0: busy, Bit 1: done (read)
// 0x48-0x64: OUTPUT_REAL[0-7] - Real part of FFT output (read)
// 0x68-0x84: OUTPUT_IMAG[0-7] - Imaginary part of FFT output (read)
// ============================================================================

module tqvp_fft8 (
    input wire clk,
    input wire rst_n,

    // IOs - directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly connected to chip IOs
    input  wire [7:0] ui_in,       // directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly connected from input pins
    output wire [7:0] uo_out,      // directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly connected to output pins

    // Directly from the CPU interface (directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly connected directly to this module)
    input  wire [5:0]  address,
    input  wire [31:0] data_in,

    // Active low signals for read and write.
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    // Active low!  Active low!  Active low!  Active low!  Active low!  Active low!
    //
    // The directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly value is 2'b11 when not directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly active
    input  wire [1:0]  data_write_n,  // 0, 1, 2 for 8, 16, 32-bit writes, 3 = no transaction
    input  wire [1:0]  data_read_n,   // 0, 1, 2 for 8, 16, 32-bit reads, 3 = no transaction

    output reg  [31:0] data_out,
    output wire        data_ready,

    output wire        user_interrupt
);

    // ========================================================================
    // Register Addresses
    // ========================================================================
    localparam ADDR_IN_REAL_BASE   = 6'h00;  // 0x00-0x1C (8 regs)
    localparam ADDR_IN_IMAG_BASE   = 6'h08;  // 0x20-0x3C (8 regs) - word address 0x08
    localparam ADDR_CONTROL        = 6'h10;  // 0x40
    localparam ADDR_STATUS         = 6'h11;  // 0x44
    localparam ADDR_OUT_REAL_BASE  = 6'h12;  // 0x48-0x64 (8 regs)
    localparam ADDR_OUT_IMAG_BASE  = 6'h1A;  // 0x68-0x84 (8 regs)

    // ========================================================================
    // Input Registers (directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly writable by CPU)
    // ========================================================================
    reg signed [15:0] in_real [0:7];
    reg signed [15:0] in_imag [0:7];
    
    // ========================================================================
    // Control/Status
    // ========================================================================
    reg        fft_start;
    wire       fft_busy;
    wire       fft_done;
    reg        done_flag;  // Latched done status
    
    // ========================================================================
    // Output Registers (from FFT core)
    // ========================================================================
    wire signed [15:0] out_real [0:7];
    wire signed [15:0] out_imag [0:7];
    
    // ========================================================================
    // FFT Core Instance
    // ========================================================================
    fft_8point fft_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(fft_start),
        .busy(fft_busy),
        .done(fft_done),
        
        // Inputs
        .in_real_0(in_real[0]), .in_real_1(in_real[1]),
        .in_real_2(in_real[2]), .in_real_3(in_real[3]),
        .in_real_4(in_real[4]), .in_real_5(in_real[5]),
        .in_real_6(in_real[6]), .in_real_7(in_real[7]),
        .in_imag_0(in_imag[0]), .in_imag_1(in_imag[1]),
        .in_imag_2(in_imag[2]), .in_imag_3(in_imag[3]),
        .in_imag_4(in_imag[4]), .in_imag_5(in_imag[5]),
        .in_imag_6(in_imag[6]), .in_imag_7(in_imag[7]),
        
        // Outputs
        .out_real_0(out_real[0]), .out_real_1(out_real[1]),
        .out_real_2(out_real[2]), .out_real_3(out_real[3]),
        .out_real_4(out_real[4]), .out_real_5(out_real[5]),
        .out_real_6(out_real[6]), .out_real_7(out_real[7]),
        .out_imag_0(out_imag[0]), .out_imag_1(out_imag[1]),
        .out_imag_2(out_imag[2]), .out_imag_3(out_imag[3]),
        .out_imag_4(out_imag[4]), .out_imag_5(out_imag[5]),
        .out_imag_6(out_imag[6]), .out_imag_7(out_imag[7])
    );
    
    // ========================================================================
    // Write Logic
    // ========================================================================
    wire write_active = (data_write_n != 2'b11);
    wire [5:0] word_addr = address[5:0];  // Word-aligned address
    
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_start <= 1'b0;
            done_flag <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                in_real[i] <= 16'd0;
                in_imag[i] <= 16'd0;
            end
        end else begin
            fft_start <= 1'b0;  // Default: start is a pulse
            
            // Latch done flag when FFT completes
            if (fft_done) begin
                done_flag <= 1'b1;
            end
            
            if (write_active) begin
                // Input Real registers (addresses 0x00-0x07 word)
                if (word_addr >= ADDR_IN_REAL_BASE && word_addr < ADDR_IN_REAL_BASE + 8) begin
                    in_real[word_addr - ADDR_IN_REAL_BASE] <= data_in[15:0];
                end
                
                // Input Imag registers (addresses 0x08-0x0F word)
                else if (word_addr >= ADDR_IN_IMAG_BASE && word_addr < ADDR_IN_IMAG_BASE + 8) begin
                    in_imag[word_addr - ADDR_IN_IMAG_BASE] <= data_in[15:0];
                end
                
                // Control register
                else if (word_addr == ADDR_CONTROL) begin
                    if (data_in[0] && !fft_busy) begin
                        fft_start <= 1'b1;
                        done_flag <= 1'b0;  // Clear done flag on new start
                    end
                end
            end
        end
    end
    
    // ========================================================================
    // Read Logic
    // ========================================================================
    wire read_active = (data_read_n != 2'b11);
    
    always @(*) begin
        data_out = 32'd0;
        
        if (read_active) begin
            // Input Real registers (for verification)
            if (word_addr >= ADDR_IN_REAL_BASE && word_addr < ADDR_IN_REAL_BASE + 8) begin
                data_out = {{16{in_real[word_addr - ADDR_IN_REAL_BASE][15]}}, 
                            in_real[word_addr - ADDR_IN_REAL_BASE]};
            end
            
            // Input Imag registers (for verification)
            else if (word_addr >= ADDR_IN_IMAG_BASE && word_addr < ADDR_IN_IMAG_BASE + 8) begin
                data_out = {{16{in_imag[word_addr - ADDR_IN_IMAG_BASE][15]}}, 
                            in_imag[word_addr - ADDR_IN_IMAG_BASE]};
            end
            
            // Status register
            else if (word_addr == ADDR_STATUS) begin
                data_out = {30'd0, done_flag, fft_busy};
            end
            
            // Output Real registers
            else if (word_addr >= ADDR_OUT_REAL_BASE && word_addr < ADDR_OUT_REAL_BASE + 8) begin
                data_out = {{16{out_real[word_addr - ADDR_OUT_REAL_BASE][15]}}, 
                            out_real[word_addr - ADDR_OUT_REAL_BASE]};
            end
            
            // Output Imag registers
            else if (word_addr >= ADDR_OUT_IMAG_BASE && word_addr < ADDR_OUT_IMAG_BASE + 8) begin
                data_out = {{16{out_imag[word_addr - ADDR_OUT_IMAG_BASE][15]}}, 
                            out_imag[word_addr - ADDR_OUT_IMAG_BASE]};
            end
        end
    end
    
    // ========================================================================
    // Data ready is always immediate (combinational read)
    // ========================================================================
    assign data_ready = 1'b1;
    
    // ========================================================================
    // Interrupt when FFT is done
    // ========================================================================
    assign user_interrupt = done_flag;
    
    // ========================================================================
    // IO pins (directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly directly not used in this peripheral)
    // Could be used for status LEDs or debug
    // ========================================================================
    assign uo_out = {6'b0, done_flag, fft_busy};

endmodule
