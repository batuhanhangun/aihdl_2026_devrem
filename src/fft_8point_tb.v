// ============================================================================
// Testbench for 8-Point FFT Module
// AI-HDL 2026 Competition - Design Phase 2
// 
// This testbench verifies the FFT with known test vectors
// DP2: Timing unchanged - testbench uses wait(done) which works with any latency
// ============================================================================

`timescale 1ns / 1ps

module fft_8point_tb;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // Clock generation (64 MHz = 15.625ns period)
    initial clk = 0;
    always #7.8125 clk = ~clk;
    
    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg         start;
    wire        busy;
    wire        done;
    
    // Input samples
    reg  signed [15:0] in_real [0:7];
    reg  signed [15:0] in_imag [0:7];
    
    // Output samples
    wire signed [15:0] out_real [0:7];
    wire signed [15:0] out_imag [0:7];
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    fft_8point dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        
        .in_real_0(in_real[0]), .in_real_1(in_real[1]),
        .in_real_2(in_real[2]), .in_real_3(in_real[3]),
        .in_real_4(in_real[4]), .in_real_5(in_real[5]),
        .in_real_6(in_real[6]), .in_real_7(in_real[7]),
        
        .in_imag_0(in_imag[0]), .in_imag_1(in_imag[1]),
        .in_imag_2(in_imag[2]), .in_imag_3(in_imag[3]),
        .in_imag_4(in_imag[4]), .in_imag_5(in_imag[5]),
        .in_imag_6(in_imag[6]), .in_imag_7(in_imag[7]),
        
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
    // Test Variables
    // ========================================================================
    integer i;
    integer test_num;
    integer errors;
    
    // Expected outputs for verification
    reg signed [15:0] expected_real [0:7];
    reg signed [15:0] expected_imag [0:7];
    
    // ========================================================================
    // Tasks
    // ========================================================================
    
    // Task to run FFT and wait for completion
    task run_fft;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            
            // Wait for done
            wait(done == 1'b1);
            @(posedge clk);
        end
    endtask
    
    // Task to display results
    task display_results;
        begin
            $display("  FFT Outputs:");
            for (i = 0; i < 8; i = i + 1) begin
                $display("    X[%0d] = %6d + j*%6d", i, out_real[i], out_imag[i]);
            end
        end
    endtask
    
    // Task to check results with tolerance
    task check_results;
        input [31:0] tolerance;
        begin
            errors = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if ((out_real[i] - expected_real[i] > tolerance) ||
                    (expected_real[i] - out_real[i] > tolerance) ||
                    (out_imag[i] - expected_imag[i] > tolerance) ||
                    (expected_imag[i] - out_imag[i] > tolerance)) begin
                    $display("  ERROR at X[%0d]: got (%d, %d), expected (%d, %d)", 
                             i, out_real[i], out_imag[i], expected_real[i], expected_imag[i]);
                    errors = errors + 1;
                end
            end
            if (errors == 0) begin
                $display("  PASS - All outputs within tolerance");
            end else begin
                $display("  FAIL - %0d errors", errors);
            end
        end
    endtask
    
    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // Setup waveform dump
        $dumpfile("fft_8point_tb.vcd");
        $dumpvars(0, fft_8point_tb);
        
        // Initialize
        rst_n = 0;
        start = 0;
        for (i = 0; i < 8; i = i + 1) begin
            in_real[i] = 0;
            in_imag[i] = 0;
        end
        
        // Reset
        #100;
        rst_n = 1;
        #100;
        
        // ====================================================================
        // Test 1: DC Signal (all ones)
        // Input: [1,1,1,1,1,1,1,1]
        // Expected: X[0] = 8, X[1..7] = 0
        // ====================================================================
        test_num = 1;
        $display("\n===========================================");
        $display("Test %0d: DC Signal (all ones)", test_num);
        $display("===========================================");
        
        for (i = 0; i < 8; i = i + 1) begin
            in_real[i] = 16'd1000;  // Scale for fixed-point
            in_imag[i] = 16'd0;
        end
        
        run_fft();
        display_results();
        
        // Expected: sum in bin 0, zeros elsewhere
        expected_real[0] = 16'd8000;  expected_imag[0] = 16'd0;
        for (i = 1; i < 8; i = i + 1) begin
            expected_real[i] = 16'd0;
            expected_imag[i] = 16'd0;
        end
        check_results(100);  // Allow small tolerance for rounding
        
        #200;
        
        // ====================================================================
        // Test 2: Impulse (delta function)
        // Input: [1,0,0,0,0,0,0,0]
        // Expected: X[k] = 1 for all k (flat spectrum)
        // ====================================================================
        test_num = 2;
        $display("\n===========================================");
        $display("Test %0d: Impulse Signal", test_num);
        $display("===========================================");
        
        in_real[0] = 16'd1000;
        in_imag[0] = 16'd0;
        for (i = 1; i < 8; i = i + 1) begin
            in_real[i] = 16'd0;
            in_imag[i] = 16'd0;
        end
        
        run_fft();
        display_results();
        
        // Expected: all bins equal
        for (i = 0; i < 8; i = i + 1) begin
            expected_real[i] = 16'd1000;
            expected_imag[i] = 16'd0;
        end
        check_results(100);
        
        #200;
        
        // ====================================================================
        // Test 3: Alternating Signal
        // Input: [1,-1,1,-1,1,-1,1,-1]
        // Expected: X[4] = 8, others = 0 (Nyquist frequency)
        // ====================================================================
        test_num = 3;
        $display("\n===========================================");
        $display("Test %0d: Alternating Signal (Nyquist)", test_num);
        $display("===========================================");
        
        for (i = 0; i < 8; i = i + 1) begin
            in_real[i] = (i % 2 == 0) ? 16'd1000 : -16'd1000;
            in_imag[i] = 16'd0;
        end
        
        run_fft();
        display_results();
        
        // Expected: peak at bin 4 (Nyquist)
        for (i = 0; i < 8; i = i + 1) begin
            expected_real[i] = 16'd0;
            expected_imag[i] = 16'd0;
        end
        expected_real[4] = 16'd8000;
        check_results(100);
        
        #200;
        
        // ====================================================================
        // Test 4: Single cycle sine wave
        // Input: sin(2*pi*n/8) for n=0..7
        // Scaled values: [0, 707, 1000, 707, 0, -707, -1000, -707]
        // Expected: energy in bins 1 and 7
        // ====================================================================
        test_num = 4;
        $display("\n===========================================");
        $display("Test %0d: Single Cycle Sine Wave", test_num);
        $display("===========================================");
        
        // sin(2*pi*n/8) * 1000
        in_real[0] = 16'd0;
        in_real[1] = 16'd707;
        in_real[2] = 16'd1000;
        in_real[3] = 16'd707;
        in_real[4] = 16'd0;
        in_real[5] = -16'd707;
        in_real[6] = -16'd1000;
        in_real[7] = -16'd707;
        
        for (i = 0; i < 8; i = i + 1) begin
            in_imag[i] = 16'd0;
        end
        
        run_fft();
        display_results();
        
        #200;
        
        // ====================================================================
        // Test 5: Two-cycle cosine wave
        // Input: cos(2*pi*2*n/8) for n=0..7
        // Expected: energy in bins 2 and 6
        // ====================================================================
        test_num = 5;
        $display("\n===========================================");
        $display("Test %0d: Two-Cycle Cosine Wave", test_num);
        $display("===========================================");
        
        // cos(2*pi*2*n/8) * 1000 = cos(pi*n/2) * 1000
        in_real[0] = 16'd1000;   // cos(0)
        in_real[1] = 16'd0;      // cos(pi/2)
        in_real[2] = -16'd1000;  // cos(pi)
        in_real[3] = 16'd0;      // cos(3pi/2)
        in_real[4] = 16'd1000;   // cos(2pi)
        in_real[5] = 16'd0;      // cos(5pi/2)
        in_real[6] = -16'd1000;  // cos(3pi)
        in_real[7] = 16'd0;      // cos(7pi/2)
        
        for (i = 0; i < 8; i = i + 1) begin
            in_imag[i] = 16'd0;
        end
        
        run_fft();
        display_results();
        
        #200;
        
        // ====================================================================
        // Done
        // ====================================================================
        $display("\n===========================================");
        $display("All tests completed!");
        $display("===========================================\n");
        
        #100;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #200000;  // DP2: Increased timeout for pipelined design
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
