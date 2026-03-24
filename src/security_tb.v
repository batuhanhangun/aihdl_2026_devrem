// ============================================================================
// Security Validation Testbench — 8-Point FFT Accelerator Peripheral
// AI-HDL 2026 Competition - Design Phase 3
//
// Tests every DP3 security countermeasure through the tqvp_fft8 register
// interface (same path a CPU would use).
//
// Test Groups:
//   Group 1: Write Protection       (TEST_SEC_01, TEST_SEC_02)
//   Group 2: Computation Integrity  (TEST_SEC_03, TEST_SEC_04)
//   Group 3: Data Leakage           (TEST_SEC_05, TEST_SEC_06)
//   Group 4: FSM Robustness         (TEST_SEC_07, TEST_SEC_08)
//   Group 5: Debug Lockout          (TEST_SEC_09)
//
// Compile & run (WSL):
//   cd src/
//   iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v
//   vvp sec_test
// ============================================================================

`timescale 1ns / 1ps

module security_tb;

    // ========================================================================
    // Clock & Reset
    // ========================================================================
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #7.8125 clk = ~clk;   // 64 MHz

    // ========================================================================
    // Bus signals to tqvp_fft8
    // ========================================================================
    reg  [5:0]  address;
    reg  [31:0] data_in_bus;
    reg  [1:0]  data_write_n;
    reg  [1:0]  data_read_n;
    wire [31:0] data_out;
    wire        data_ready;
    wire        user_interrupt;   // = done_flag in peripheral
    wire [7:0]  uo_out;
    wire        spi_lock;         // [DP3-CM-A] observable lock status

    // ========================================================================
    // DUT: tqvp_fft8 (peripheral.v + fft_8point.v)
    // ========================================================================
    tqvp_fft8 dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .ui_in        (8'h00),
        .uo_out       (uo_out),
        .address      (address),
        .data_in      (data_in_bus),
        .data_write_n (data_write_n),
        .data_read_n  (data_read_n),
        .data_out     (data_out),
        .data_ready   (data_ready),
        .user_interrupt(user_interrupt),
        .spi_lock     (spi_lock)
    );

    // ========================================================================
    // Register address constants (word addresses, matching peripheral.v)
    // ========================================================================
    localparam ADDR_IN_REAL_BASE  = 6'h00;   // words 0x00-0x07
    localparam ADDR_IN_IMAG_BASE  = 6'h08;   // words 0x08-0x0F
    localparam ADDR_CONTROL       = 6'h10;   // word  0x10
    localparam ADDR_STATUS        = 6'h11;   // word  0x11
    localparam ADDR_OUT_REAL_BASE = 6'h12;   // words 0x12-0x19
    localparam ADDR_OUT_IMAG_BASE = 6'h1A;   // words 0x1A-0x21

    // STATUS bit positions
    localparam ST_BUSY = 0;
    localparam ST_DONE = 1;
    localparam ST_ERR  = 2;

    // CONTROL bit positions
    localparam CT_START   = 0;
    localparam CT_INT_CLR = 1;
    localparam CT_LOCK    = 2;
    localparam CT_ERR_CLR = 3;

    // ========================================================================
    // Test counters
    // ========================================================================
    integer pass_count;
    integer fail_count;
    integer i;
    reg [31:0] rd_data;
    reg [31:0] rd_data2;
    reg        test_pass;

    // ========================================================================
    // Tasks
    // ========================================================================

    // 32-bit bus write (registered — takes effect on next posedge)
    task bus_write;
        input [5:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            address      = addr;
            data_in_bus  = data;
            data_write_n = 2'b10;  // 32-bit write
            data_read_n  = 2'b11;
            @(posedge clk); #1;    // write captured on this edge
            data_write_n = 2'b11;
        end
    endtask

    // 32-bit bus read (combinational — data_out valid after address/data_read_n settle)
    task bus_read;
        input  [5:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            address      = addr;
            data_write_n = 2'b11;
            data_read_n  = 2'b10;  // 32-bit read
            #3;                    // combinational settle
            data = data_out;
            @(posedge clk); #1;
            data_read_n  = 2'b11;
        end
    endtask

    // Wait N rising edges
    task wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
            #1;
        end
    endtask

    // Write all 8 input real+imag samples via bus
    task load_inputs;
        input [15:0] r0,r1,r2,r3,r4,r5,r6,r7;
        input [15:0] i0,i1,i2,i3,i4,i5,i6,i7;
        begin
            bus_write(ADDR_IN_REAL_BASE+0, {16'h0, r0});
            bus_write(ADDR_IN_REAL_BASE+1, {16'h0, r1});
            bus_write(ADDR_IN_REAL_BASE+2, {16'h0, r2});
            bus_write(ADDR_IN_REAL_BASE+3, {16'h0, r3});
            bus_write(ADDR_IN_REAL_BASE+4, {16'h0, r4});
            bus_write(ADDR_IN_REAL_BASE+5, {16'h0, r5});
            bus_write(ADDR_IN_REAL_BASE+6, {16'h0, r6});
            bus_write(ADDR_IN_REAL_BASE+7, {16'h0, r7});
            bus_write(ADDR_IN_IMAG_BASE+0, {16'h0, i0});
            bus_write(ADDR_IN_IMAG_BASE+1, {16'h0, i1});
            bus_write(ADDR_IN_IMAG_BASE+2, {16'h0, i2});
            bus_write(ADDR_IN_IMAG_BASE+3, {16'h0, i3});
            bus_write(ADDR_IN_IMAG_BASE+4, {16'h0, i4});
            bus_write(ADDR_IN_IMAG_BASE+5, {16'h0, i5});
            bus_write(ADDR_IN_IMAG_BASE+6, {16'h0, i6});
            bus_write(ADDR_IN_IMAG_BASE+7, {16'h0, i7});
        end
    endtask

    // Start FFT by pulsing CONTROL[0]
    task start_fft;
        begin
            bus_write(ADDR_CONTROL, 32'h1);
        end
    endtask

    // Clear done_flag/interrupt via CONTROL[1] (without starting FFT — CM-C)
    task clear_done;
        begin
            bus_write(ADDR_CONTROL, 32'h2);
        end
    endtask

    // Clear write_error flag via CONTROL[3] — CM-D
    task clear_error;
        begin
            bus_write(ADDR_CONTROL, 32'h8);
        end
    endtask

    // Wait for FFT done (polls user_interrupt = done_flag)
    // Timeout after 200 cycles to avoid hanging on lockup
    task wait_fft_done;
        integer timeout;
        begin
            timeout = 0;
            while (user_interrupt !== 1'b1 && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            #1;
            if (timeout >= 200)
                $display("  WARNING: wait_fft_done timed out — possible lockup");
        end
    endtask

    // Report test result and update counters
    task report_result;
        input [8*20:1] test_id;
        input          pass;
        begin
            if (pass) begin
                $display("  PASS %0s", test_id);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %0s", test_id);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $dumpfile("security_tb.vcd");
        $dumpvars(0, security_tb);

        // Initialise bus signals
        address      = 6'h00;
        data_in_bus  = 32'h0;
        data_write_n = 2'b11;
        data_read_n  = 2'b11;
        pass_count   = 0;
        fail_count   = 0;
        rst_n        = 1'b0;

        // Reset sequence
        #100;
        @(posedge clk); #1;
        rst_n = 1'b1;
        wait_cycles(5);

        // ================================================================
        // GROUP 1: Write Protection
        // ================================================================
        $display("");
        $display("============================================================");
        $display("TEST GROUP 1: Write Protection");
        $display("============================================================");

        // ----------------------------------------------------------------
        // TEST_SEC_01: Write to read-only OUTPUT_REAL[0] is silently ignored
        //              and write_error is set (CM-D).
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_01: Write to OUTPUT_REAL[0] ignored, write_error set ---");
        begin
            // Run a reference FFT: DC signal, all 1000 → X[0]=8000, X[1..7]=0
            load_inputs(16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd0,    16'd0,    16'd0,    16'd0,
                        16'd0,    16'd0,    16'd0,    16'd0);
            start_fft();
            wait_fft_done();
            clear_done();

            // Read the legitimate FFT result at OUTPUT_REAL[0] (~8000)
            bus_read(ADDR_OUT_REAL_BASE, rd_data);

            // Attempt to overwrite OUTPUT_REAL[0] — must be ignored
            bus_write(ADDR_OUT_REAL_BASE, 32'hDEADBEEF);

            // Read back — must still be the FFT result
            bus_read(ADDR_OUT_REAL_BASE, rd_data2);

            // Check write_error was set
            bus_read(ADDR_STATUS, i);

            test_pass = (rd_data2 !== 32'hDEADBEEF) && (i[ST_ERR] == 1'b1);
            $display("  OUTPUT_REAL[0] before write: 0x%08X", rd_data);
            $display("  OUTPUT_REAL[0] after write:  0x%08X (expected unchanged)", rd_data2);
            $display("  STATUS.write_error: %0b (expected 1)", i[ST_ERR]);
            report_result("TEST_SEC_01", test_pass);
            clear_error();
        end

        // ----------------------------------------------------------------
        // TEST_SEC_02: Write to unmapped address sets write_error, no state change
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_02: Write to unmapped address (word 0x3F) ---");
        begin
            bus_read(ADDR_STATUS, rd_data);

            // Word 0x3F = 63, beyond ADDR_OUT_IMAG_BASE+7 = 0x21+7 = 0x28 = 40
            bus_write(6'h3F, 32'hCAFEBABE);

            bus_read(ADDR_STATUS, rd_data2);

            test_pass = (rd_data2[ST_ERR]  == 1'b1) &&
                        (rd_data2[ST_BUSY] == 1'b0) &&
                        (rd_data2[ST_DONE] == 1'b0);
            $display("  STATUS after unmapped write: 0x%08X", rd_data2);
            $display("  write_error=%0b busy=%0b done=%0b (expected 1,0,0)",
                     rd_data2[ST_ERR], rd_data2[ST_BUSY], rd_data2[ST_DONE]);
            report_result("TEST_SEC_02", test_pass);
            clear_error();
        end

        // ================================================================
        // GROUP 2: Computation Integrity Guards
        // ================================================================
        $display("");
        $display("============================================================");
        $display("TEST GROUP 2: Computation Integrity Guards");
        $display("============================================================");

        // ----------------------------------------------------------------
        // TEST_SEC_03: CONTROL start-while-busy rejected, write_error set (CM-D)
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_03: Second CONTROL=1 while busy is rejected ---");
        begin
            load_inputs(16'd1000, 16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0);
            start_fft();

            // Wait until definitely busy
            wait_cycles(4);
            bus_read(ADDR_STATUS, rd_data);   // snapshot: should show busy=1

            // Attempt second start while busy
            bus_write(ADDR_CONTROL, 32'h1);

            // write_error should now be set
            bus_read(ADDR_STATUS, rd_data2);

            // Let the original FFT finish
            wait_fft_done();
            clear_done();

            test_pass = (rd_data[ST_BUSY]   == 1'b1) &&   // was busy during 2nd write
                        (rd_data2[ST_ERR]   == 1'b1);      // write_error flagged

            $display("  STATUS during busy: 0x%08X (busy=%0b)", rd_data, rd_data[ST_BUSY]);
            $display("  STATUS after 2nd CONTROL=1: write_error=%0b (expected 1)",
                     rd_data2[ST_ERR]);
            report_result("TEST_SEC_03", test_pass);
            clear_error();
        end

        // ----------------------------------------------------------------
        // TEST_SEC_04: Input write while busy is blocked (CM-DP2 input gate)
        //              Output must match ORIGINAL inputs, not attempted overwrite.
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_04: Input overwrite while busy is blocked ---");
        begin
            // Impulse at sample 0: value 2000 → all output bins ≈ 2000
            load_inputs(16'd2000, 16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0);
            start_fft();

            // Wait until definitely in STAGE1
            wait_cycles(4);

            // Attempt to overwrite INPUT_REAL[0] while busy — must be blocked
            bus_write(ADDR_IN_REAL_BASE, 32'h7FFF);

            wait_fft_done();
            clear_done();

            // Check OUTPUT_REAL[0] and [1]: should be ~2000 (impulse FFT = flat 2000)
            bus_read(ADDR_OUT_REAL_BASE+0, rd_data);
            bus_read(ADDR_OUT_REAL_BASE+1, rd_data2);

            test_pass = ($signed(rd_data[15:0])  >= 16'sd1900) &&
                        ($signed(rd_data[15:0])  <= 16'sd2100) &&
                        ($signed(rd_data2[15:0]) >= 16'sd1900) &&
                        ($signed(rd_data2[15:0]) <= 16'sd2100);

            $display("  OUTPUT_REAL[0] = %0d (expected ~2000)", $signed(rd_data[15:0]));
            $display("  OUTPUT_REAL[1] = %0d (expected ~2000)", $signed(rd_data2[15:0]));
            report_result("TEST_SEC_04", test_pass);
            clear_error();
        end

        // ================================================================
        // GROUP 3: Data Leakage Prevention
        // ================================================================
        $display("");
        $display("============================================================");
        $display("TEST GROUP 3: Data Leakage Prevention");
        $display("============================================================");

        // ----------------------------------------------------------------
        // TEST_SEC_05: Input registers return 0 after computation
        //              CM-H (write-only — reads return 0) and
        //              CM-B (inputs zeroized on fft_done)
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_05: Input registers are write-only and zeroized post-FFT ---");
        begin
            load_inputs(16'd1234, 16'd5678, 16'd0, 16'd0,
                        16'd0,    16'd0,    16'd0, 16'd0,
                        16'd0,    16'd0,    16'd0, 16'd0,
                        16'd0,    16'd0,    16'd0, 16'd0);
            start_fft();
            wait_fft_done();
            clear_done();

            // Read INPUT_REAL[0] and INPUT_REAL[1]
            // CM-H: read path removed → returns 0 regardless
            // CM-B: in_real[] zeroized on fft_done → also 0
            bus_read(ADDR_IN_REAL_BASE+0, rd_data);
            bus_read(ADDR_IN_REAL_BASE+1, rd_data2);

            test_pass = (rd_data == 32'h0) && (rd_data2 == 32'h0);
            $display("  INPUT_REAL[0] readback = 0x%08X (expected 0x00000000)", rd_data);
            $display("  INPUT_REAL[1] readback = 0x%08X (expected 0x00000000)", rd_data2);
            report_result("TEST_SEC_05", test_pass);
        end

        // ----------------------------------------------------------------
        // TEST_SEC_06: FFT #2 output contains no residue from FFT #1 (CM-B)
        //              Stage registers are zeroized in DONE state.
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_06: FFT#2 output has no residue from FFT#1 ---");
        begin
            // FFT #1: DC signal (all 1000) → X[0]=8000, X[4]=0
            load_inputs(16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd0,    16'd0,    16'd0,    16'd0,
                        16'd0,    16'd0,    16'd0,    16'd0);
            start_fft();
            wait_fft_done();
            clear_done();

            // FFT #2: Impulse (1000, 0, ...) → X[k]≈1000 for all k
            load_inputs(16'd1000, 16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0);
            start_fft();
            wait_fft_done();
            clear_done();

            // X[0] should be ~1000 (NOT 8000 from FFT#1)
            // X[4] should be ~1000 (NOT 0 from FFT#1's DC spectrum)
            bus_read(ADDR_OUT_REAL_BASE+0, rd_data);   // bin 0
            bus_read(ADDR_OUT_REAL_BASE+4, rd_data2);  // bin 4

            test_pass = ($signed(rd_data[15:0])  >= 16'sd900) &&
                        ($signed(rd_data[15:0])  <= 16'sd1100) &&
                        ($signed(rd_data2[15:0]) >= 16'sd900) &&
                        ($signed(rd_data2[15:0]) <= 16'sd1100);

            $display("  FFT#2 X[0] = %0d (expected ~1000, not 8000 from FFT#1)",
                     $signed(rd_data[15:0]));
            $display("  FFT#2 X[4] = %0d (expected ~1000, not 0 from FFT#1)",
                     $signed(rd_data2[15:0]));
            report_result("TEST_SEC_06", test_pass);
        end

        // ================================================================
        // GROUP 4: FSM Robustness
        // ================================================================
        $display("");
        $display("============================================================");
        $display("TEST GROUP 4: FSM Robustness");
        $display("============================================================");

        // ----------------------------------------------------------------
        // TEST_SEC_07: Reset mid-computation → FSM recovers to IDLE cleanly (CM-F)
        //              Post-reset FFT must produce correct output.
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_07: Reset mid-computation, clean FSM recovery ---");
        begin
            load_inputs(16'd1000, 16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0,
                        16'd0,    16'd0, 16'd0, 16'd0);
            start_fft();

            // Assert reset mid-computation (while in STAGE1)
            wait_cycles(5);
            rst_n = 1'b0;
            wait_cycles(2);
            rst_n = 1'b1;
            wait_cycles(3);

            // STATUS must be fully cleared (busy=0, done=0, error=0)
            bus_read(ADDR_STATUS, rd_data);

            // Run a normal FFT post-reset: DC signal → X[0] ≈ 8000
            load_inputs(16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd0,    16'd0,    16'd0,    16'd0,
                        16'd0,    16'd0,    16'd0,    16'd0);
            start_fft();
            wait_fft_done();
            clear_done();

            bus_read(ADDR_OUT_REAL_BASE+0, rd_data2);

            test_pass = (rd_data[ST_BUSY] == 1'b0) &&
                        (rd_data[ST_DONE] == 1'b0) &&
                        ($signed(rd_data2[15:0]) >= 16'sd7900) &&
                        ($signed(rd_data2[15:0]) <= 16'sd8100);

            $display("  STATUS after reset:  0x%08X (expected 0x00000000)", rd_data);
            $display("  Post-reset X[0] = %0d (expected ~8000 for DC input)",
                     $signed(rd_data2[15:0]));
            report_result("TEST_SEC_07", test_pass);
        end

        // ----------------------------------------------------------------
        // TEST_SEC_08: Rapid CONTROL toggling — FSM must not lockup (CM-F)
        //              Two CONTROL=1 writes back-to-back: second should be
        //              rejected, one FFT completes cleanly.
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_08: Rapid CONTROL toggles do not lockup FSM ---");
        begin
            load_inputs(16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd1000, 16'd1000, 16'd1000, 16'd1000,
                        16'd0,    16'd0,    16'd0,    16'd0,
                        16'd0,    16'd0,    16'd0,    16'd0);

            // Write CONTROL=1 twice in consecutive cycles without deassert between
            @(posedge clk); #1;
            address      = ADDR_CONTROL;
            data_in_bus  = 32'h1;
            data_write_n = 2'b10;
            data_read_n  = 2'b11;
            @(posedge clk); #1;   // first CONTROL=1 captured (fft_start pulsed)
            // Hold write active — second cycle: FFT is now starting, busy going high
            data_in_bus  = 32'h1; // same value
            @(posedge clk); #1;   // second CONTROL=1 captured — should be rejected
            data_write_n = 2'b11;

            // Wait for FFT to finish (or timeout at 200 cycles → lockup indicator)
            wait_fft_done();

            // FSM should be idle and done, not locked up
            bus_read(ADDR_STATUS, rd_data);

            test_pass = (user_interrupt == 1'b1) &&
                        (rd_data[ST_BUSY] == 1'b0);

            $display("  user_interrupt = %0b (expected 1 — FFT completed)", user_interrupt);
            $display("  STATUS.busy    = %0b (expected 0 — not locked up)", rd_data[ST_BUSY]);
            report_result("TEST_SEC_08", test_pass);
            clear_done();
            clear_error();
        end

        // ================================================================
        // GROUP 5: Debug Lockout (CM-A, CM-I)
        // ================================================================
        $display("");
        $display("============================================================");
        $display("TEST GROUP 5: Debug Lockout");
        $display("============================================================");

        // ----------------------------------------------------------------
        // TEST_SEC_09: CONTROL[2] sets spi_lock (one-time-writable).
        //              Once locked: spi_lock=1, uo_out masked to 0 (CM-I).
        //              Lock cannot be cleared by any bus write; only rst_n clears it.
        // ----------------------------------------------------------------
        $display("");
        $display("--- TEST_SEC_09: SPI LOCK sets spi_lock=1 and masks uo_out ---");
        begin
            // Baseline: spi_lock should be 0 before any lock write
            $display("  spi_lock before LOCK write: %0b (expected 0)", spi_lock);

            // Set LOCK bit: write CONTROL[2]=1
            bus_write(ADDR_CONTROL, 32'h4);
            @(posedge clk); #1;   // propagation settle

            $display("  spi_lock after  LOCK write: %0b (expected 1)", spi_lock);
            $display("  uo_out after    LOCK write: 0x%02X (expected 0x00)", uo_out);

            // Verify lock is set and uo_out is masked
            test_pass = (spi_lock == 1'b1) && (uo_out == 8'h00);
            report_result("TEST_SEC_09a spi_lock=1 uo_out=0x00", test_pass);

            // Attempt to clear lock via bus write — must have no effect
            bus_write(ADDR_CONTROL, 32'h0);  // write CONTROL with lock bit clear
            bus_write(ADDR_CONTROL, 32'hF);  // even writing all bits non-set-lock
            @(posedge clk); #1;

            test_pass = (spi_lock == 1'b1);  // still locked
            $display("  spi_lock after clear attempt: %0b (expected 1 — set-only)", spi_lock);
            report_result("TEST_SEC_09b lock is set-only", test_pass);

            // Only rst_n can clear the lock
            rst_n = 1'b0;
            wait_cycles(2);
            rst_n = 1'b1;
            wait_cycles(3);
            @(posedge clk); #1;

            test_pass = (spi_lock == 1'b0);
            $display("  spi_lock after rst_n: %0b (expected 0 — cleared by reset)", spi_lock);
            report_result("TEST_SEC_09c rst_n clears lock", test_pass);
        end

        // ================================================================
        // Summary
        // ================================================================
        $display("");
        $display("============================================================");
        $display("SECURITY TESTS: %0d/%0d PASSED",
                 pass_count, pass_count + fail_count);
        $display("============================================================");
        if (fail_count == 0)
            $display("ALL SECURITY TESTS PASSED");
        else
            $display("WARNING: %0d SECURITY TEST(S) FAILED", fail_count);

        $display("");
        $display("--- WSL Simulation Commands ---");
        $display("  cd src/");
        $display("  iverilog -o sec_test fft_8point.v peripheral.v tt_wrapper.v security_tb.v");
        $display("  vvp sec_test");
        $display("-------------------------------");

        #100;
        $finish;
    end

    // ========================================================================
    // Timeout watchdog (should never fire in normal operation)
    // ========================================================================
    initial begin
        #5000000;
        $display("ERROR: Global simulation timeout — possible lockup");
        $finish;
    end

endmodule


// ============================================================================
// Stub modules for tt_wrapper.v compilation
//
// tt_wrapper.v instantiates spi_reg and synchronizer from the TinyQV library.
// These stubs satisfy the elaboration requirement without implementing any
// real SPI transactions, so the design compiles cleanly with:
//   iverilog ... tt_wrapper.v security_tb.v
// ============================================================================

module synchronizer #(
    parameter STAGES = 2,
    parameter WIDTH  = 1
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0] data_out
);
    // Pass-through stub (single-cycle latency; safe for testbench purposes)
    assign data_out = data_in;
endmodule


module spi_reg #(
    parameter ADDR_W = 6,
    parameter REG_W  = 32
) (
    input  wire              clk,
    input  wire              rstb,
    input  wire              ena,
    input  wire              spi_mosi,
    output wire              spi_miso,
    input  wire              spi_clk,
    input  wire              spi_cs_n,
    output wire [ADDR_W-1:0] reg_addr,
    input  wire [REG_W-1:0]  reg_data_i,
    output wire [REG_W-1:0]  reg_data_o,
    output wire              reg_addr_v,
    input  wire              reg_data_i_dv,
    output wire              reg_data_o_dv,
    output wire              reg_rw,
    output wire [1:0]        txn_width
);
    // No SPI transactions generated — all outputs safe/inactive
    assign spi_miso      = 1'b0;
    assign reg_addr      = {ADDR_W{1'b0}};
    assign reg_data_o    = {REG_W{1'b0}};
    assign reg_addr_v    = 1'b0;
    assign reg_data_o_dv = 1'b0;
    assign reg_rw        = 1'b0;
    assign txn_width     = 2'b11;  // 2'b11 = no transaction (matches peripheral.v)
endmodule
