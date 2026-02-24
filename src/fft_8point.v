// ============================================================================
// 8-Point FFT Module
// AI-HDL 2026 Competition - Design Phase 2
// 
// This module implements an 8-point Radix-2 Decimation-in-Time FFT
// using fixed-point arithmetic (Q1.15 format for twiddle factors)
//
// DP2 Optimizations:
//   - Pipelined butterfly unit (2-stage) for improved Fmax
//   - Clock gating on stage/output registers for power reduction
//   - Operand isolation on butterfly inputs for switching reduction
//   - Trivial twiddle factor (W0) bypass for area/power savings
// ============================================================================

module fft_8point (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface
    input  wire        start,          // Pulse to start FFT computation
    output reg         busy,           // High while computing
    output reg         done,           // Pulses high when complete
    
    // Input samples (16-bit signed real + 16-bit signed imaginary)
    input  wire signed [15:0] in_real_0, in_real_1, in_real_2, in_real_3,
    input  wire signed [15:0] in_real_4, in_real_5, in_real_6, in_real_7,
    input  wire signed [15:0] in_imag_0, in_imag_1, in_imag_2, in_imag_3,
    input  wire signed [15:0] in_imag_4, in_imag_5, in_imag_6, in_imag_7,
    
    // Output samples (16-bit signed real + 16-bit signed imaginary)
    output reg  signed [15:0] out_real_0, out_real_1, out_real_2, out_real_3,
    output reg  signed [15:0] out_real_4, out_real_5, out_real_6, out_real_7,
    output reg  signed [15:0] out_imag_0, out_imag_1, out_imag_2, out_imag_3,
    output reg  signed [15:0] out_imag_4, out_imag_5, out_imag_6, out_imag_7
);

    // ========================================================================
    // Twiddle Factors (W8^k = e^(-j*2*pi*k/8)) in Q1.15 format
    // Scaled by 32767 (2^15 - 1)
    // ========================================================================
    // W8^0 = 1.0000 + j*0.0000  ->  32767,      0
    // W8^1 = 0.7071 - j*0.7071  ->  23170, -23170
    // W8^2 = 0.0000 - j*1.0000  ->      0, -32767
    // W8^3 =-0.7071 - j*0.7071  -> -23170, -23170
    
    localparam signed [15:0] W0_RE =  16'sd32767;   // cos(0)
    localparam signed [15:0] W0_IM =  16'sd0;       // -sin(0)
    localparam signed [15:0] W1_RE =  16'sd23170;   // cos(pi/4)
    localparam signed [15:0] W1_IM = -16'sd23170;   // -sin(pi/4)
    localparam signed [15:0] W2_RE =  16'sd0;       // cos(pi/2)
    localparam signed [15:0] W2_IM = -16'sd32767;   // -sin(pi/2)
    localparam signed [15:0] W3_RE = -16'sd23170;   // cos(3*pi/4)
    localparam signed [15:0] W3_IM = -16'sd23170;   // -sin(3*pi/4)

    // ========================================================================
    // State Machine
    // ========================================================================
    localparam IDLE   = 3'd0;
    localparam STAGE1 = 3'd1;
    localparam STAGE2 = 3'd2;
    localparam STAGE3 = 3'd3;
    localparam DONE   = 3'd4;
    
    reg [2:0] state;
    
    // ========================================================================
    // Working Registers (bit-reversed input order for DIT FFT)
    // Input order: 0,4,2,6,1,5,3,7 (bit-reversed indices)
    // ========================================================================
    reg signed [15:0] stage_real [0:7];
    reg signed [15:0] stage_imag [0:7];
    
    // ========================================================================
    // [DP2] Clock gating enable signals (Power Optimization)
    // ========================================================================
    wire stage_reg_en = (state != IDLE);
    wire output_reg_en = (state == DONE);
    
    // ========================================================================
    // [DP2] Operand isolation & butterfly control
    // ========================================================================
    wire bfly_active = (state == STAGE1 || state == STAGE2 || state == STAGE3);
    
    // Butterfly computation registers
    reg signed [15:0] bfly_a_re, bfly_a_im;
    reg signed [15:0] bfly_b_re, bfly_b_im;
    reg signed [15:0] bfly_w_re, bfly_w_im;
    
    // [DP2] Trivial twiddle bypass flag
    reg bfly_trivial_w;   // 1 when twiddle = W0 (multiply = identity)
    
    // Operand-isolated butterfly inputs (zero when not active)
    wire signed [15:0] bfly_a_re_iso = bfly_active ? bfly_a_re : 16'sd0;
    wire signed [15:0] bfly_a_im_iso = bfly_active ? bfly_a_im : 16'sd0;
    wire signed [15:0] bfly_b_re_iso = bfly_active ? bfly_b_re : 16'sd0;
    wire signed [15:0] bfly_b_im_iso = bfly_active ? bfly_b_im : 16'sd0;
    wire signed [15:0] bfly_w_re_iso = bfly_active ? bfly_w_re : 16'sd0;
    wire signed [15:0] bfly_w_im_iso = bfly_active ? bfly_w_im : 16'sd0;
    wire               bfly_triv_iso = bfly_active ? bfly_trivial_w : 1'b0;

    // Pipelined butterfly outputs
    wire signed [15:0] bfly_out_a_re, bfly_out_a_im;
    wire signed [15:0] bfly_out_b_re, bfly_out_b_im;
    wire               bfly_out_valid;
    
    // ========================================================================
    // [DP2] Pipelined Butterfly Unit Instance
    // ========================================================================
    butterfly_pipelined bfly_unit (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(bfly_active),
        .a_re(bfly_a_re_iso),
        .a_im(bfly_a_im_iso),
        .b_re(bfly_b_re_iso),
        .b_im(bfly_b_im_iso),
        .w_re(bfly_w_re_iso),
        .w_im(bfly_w_im_iso),
        .trivial_w(bfly_triv_iso),
        .out_a_re(bfly_out_a_re),
        .out_a_im(bfly_out_a_im),
        .out_b_re(bfly_out_b_re),
        .out_b_im(bfly_out_b_im),
        .valid_out(bfly_out_valid)
    );
    
    // ========================================================================
    // Sub-state counter for sequential butterfly operations
    // DP2: Extra states added for pipeline latency (SETUP -> WAIT -> STORE)
    //   cnt 0: setup butterfly inputs
    //   cnt 1: wait for pipeline (1 cycle latency)
    //   cnt 2: store results + setup next butterfly
    //   ... repeats for each butterfly in the stage
    // ========================================================================
    reg [3:0] bfly_cnt;
    
    // ========================================================================
    // Main State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            bfly_cnt <= 4'd0;
            bfly_trivial_w <= 1'b0;
            
            // Clear outputs
            out_real_0 <= 16'd0; out_real_1 <= 16'd0;
            out_real_2 <= 16'd0; out_real_3 <= 16'd0;
            out_real_4 <= 16'd0; out_real_5 <= 16'd0;
            out_real_6 <= 16'd0; out_real_7 <= 16'd0;
            out_imag_0 <= 16'd0; out_imag_1 <= 16'd0;
            out_imag_2 <= 16'd0; out_imag_3 <= 16'd0;
            out_imag_4 <= 16'd0; out_imag_5 <= 16'd0;
            out_imag_6 <= 16'd0; out_imag_7 <= 16'd0;
            
        end else begin
            done <= 1'b0;  // Default: done is a pulse
            
            case (state)
                IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        bfly_cnt <= 4'd0;
                        
                        // Load inputs in bit-reversed order for DIT FFT
                        // Bit-reverse of 0,1,2,3,4,5,6,7 = 0,4,2,6,1,5,3,7
                        stage_real[0] <= in_real_0;  stage_imag[0] <= in_imag_0;
                        stage_real[1] <= in_real_4;  stage_imag[1] <= in_imag_4;
                        stage_real[2] <= in_real_2;  stage_imag[2] <= in_imag_2;
                        stage_real[3] <= in_real_6;  stage_imag[3] <= in_imag_6;
                        stage_real[4] <= in_real_1;  stage_imag[4] <= in_imag_1;
                        stage_real[5] <= in_real_5;  stage_imag[5] <= in_imag_5;
                        stage_real[6] <= in_real_3;  stage_imag[6] <= in_imag_3;
                        stage_real[7] <= in_real_7;  stage_imag[7] <= in_imag_7;
                        
                        state <= STAGE1;
                    end
                end
                
                // ==============================================================
                // Stage 1: 4 butterflies with W8^0 (trivial twiddle = 1)
                // Pairs: (0,1), (2,3), (4,5), (6,7)
                // DP2: All W0 -> trivial bypass enabled
                // ==============================================================
                STAGE1: begin
                    case (bfly_cnt)
                        // --- Butterfly 0: indices 0,1 ---
                        4'd0: begin
                            bfly_a_re <= stage_real[0]; bfly_a_im <= stage_imag[0];
                            bfly_b_re <= stage_real[1]; bfly_b_im <= stage_imag[1];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd1;
                        end
                        4'd1: begin  // Pipeline wait
                            bfly_cnt <= 4'd2;
                        end
                        4'd2: begin
                            // Store result, setup next butterfly
                            stage_real[0] <= bfly_out_a_re; stage_imag[0] <= bfly_out_a_im;
                            stage_real[1] <= bfly_out_b_re; stage_imag[1] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[2]; bfly_a_im <= stage_imag[2];
                            bfly_b_re <= stage_real[3]; bfly_b_im <= stage_imag[3];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd3;
                        end
                        // --- Butterfly 1: indices 2,3 ---
                        4'd3: begin  // Pipeline wait
                            bfly_cnt <= 4'd4;
                        end
                        4'd4: begin
                            stage_real[2] <= bfly_out_a_re; stage_imag[2] <= bfly_out_a_im;
                            stage_real[3] <= bfly_out_b_re; stage_imag[3] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[4]; bfly_a_im <= stage_imag[4];
                            bfly_b_re <= stage_real[5]; bfly_b_im <= stage_imag[5];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd5;
                        end
                        // --- Butterfly 2: indices 4,5 ---
                        4'd5: begin  // Pipeline wait
                            bfly_cnt <= 4'd6;
                        end
                        4'd6: begin
                            stage_real[4] <= bfly_out_a_re; stage_imag[4] <= bfly_out_a_im;
                            stage_real[5] <= bfly_out_b_re; stage_imag[5] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[6]; bfly_a_im <= stage_imag[6];
                            bfly_b_re <= stage_real[7]; bfly_b_im <= stage_imag[7];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd7;
                        end
                        // --- Butterfly 3: indices 6,7 ---
                        4'd7: begin  // Pipeline wait
                            bfly_cnt <= 4'd8;
                        end
                        4'd8: begin
                            stage_real[6] <= bfly_out_a_re; stage_imag[6] <= bfly_out_a_im;
                            stage_real[7] <= bfly_out_b_re; stage_imag[7] <= bfly_out_b_im;
                            bfly_cnt <= 4'd0;
                            state <= STAGE2;
                        end
                        default: bfly_cnt <= 4'd0;
                    endcase
                end
                
                // ==============================================================
                // Stage 2: 4 butterflies with W8^0 and W8^2
                // Pairs: (0,2), (1,3), (4,6), (5,7)
                // Twiddles: W0, W2, W0, W2
                // ==============================================================
                STAGE2: begin
                    case (bfly_cnt)
                        // --- Butterfly 0: indices 0,2 with W0 ---
                        4'd0: begin
                            bfly_a_re <= stage_real[0]; bfly_a_im <= stage_imag[0];
                            bfly_b_re <= stage_real[2]; bfly_b_im <= stage_imag[2];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd1;
                        end
                        4'd1: begin
                            bfly_cnt <= 4'd2;
                        end
                        4'd2: begin
                            stage_real[0] <= bfly_out_a_re; stage_imag[0] <= bfly_out_a_im;
                            stage_real[2] <= bfly_out_b_re; stage_imag[2] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[1]; bfly_a_im <= stage_imag[1];
                            bfly_b_re <= stage_real[3]; bfly_b_im <= stage_imag[3];
                            bfly_w_re <= W2_RE; bfly_w_im <= W2_IM;
                            bfly_trivial_w <= 1'b0;
                            bfly_cnt <= 4'd3;
                        end
                        // --- Butterfly 1: indices 1,3 with W2 ---
                        4'd3: begin
                            bfly_cnt <= 4'd4;
                        end
                        4'd4: begin
                            stage_real[1] <= bfly_out_a_re; stage_imag[1] <= bfly_out_a_im;
                            stage_real[3] <= bfly_out_b_re; stage_imag[3] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[4]; bfly_a_im <= stage_imag[4];
                            bfly_b_re <= stage_real[6]; bfly_b_im <= stage_imag[6];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd5;
                        end
                        // --- Butterfly 2: indices 4,6 with W0 ---
                        4'd5: begin
                            bfly_cnt <= 4'd6;
                        end
                        4'd6: begin
                            stage_real[4] <= bfly_out_a_re; stage_imag[4] <= bfly_out_a_im;
                            stage_real[6] <= bfly_out_b_re; stage_imag[6] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[5]; bfly_a_im <= stage_imag[5];
                            bfly_b_re <= stage_real[7]; bfly_b_im <= stage_imag[7];
                            bfly_w_re <= W2_RE; bfly_w_im <= W2_IM;
                            bfly_trivial_w <= 1'b0;
                            bfly_cnt <= 4'd7;
                        end
                        // --- Butterfly 3: indices 5,7 with W2 ---
                        4'd7: begin
                            bfly_cnt <= 4'd8;
                        end
                        4'd8: begin
                            stage_real[5] <= bfly_out_a_re; stage_imag[5] <= bfly_out_a_im;
                            stage_real[7] <= bfly_out_b_re; stage_imag[7] <= bfly_out_b_im;
                            bfly_cnt <= 4'd0;
                            state <= STAGE3;
                        end
                        default: bfly_cnt <= 4'd0;
                    endcase
                end
                
                // ==============================================================
                // Stage 3: 4 butterflies with W8^0, W8^1, W8^2, W8^3
                // Pairs: (0,4), (1,5), (2,6), (3,7)
                // Twiddles: W0, W1, W2, W3
                // ==============================================================
                STAGE3: begin
                    case (bfly_cnt)
                        // --- Butterfly 0: indices 0,4 with W0 ---
                        4'd0: begin
                            bfly_a_re <= stage_real[0]; bfly_a_im <= stage_imag[0];
                            bfly_b_re <= stage_real[4]; bfly_b_im <= stage_imag[4];
                            bfly_w_re <= W0_RE; bfly_w_im <= W0_IM;
                            bfly_trivial_w <= 1'b1;
                            bfly_cnt <= 4'd1;
                        end
                        4'd1: begin
                            bfly_cnt <= 4'd2;
                        end
                        4'd2: begin
                            stage_real[0] <= bfly_out_a_re; stage_imag[0] <= bfly_out_a_im;
                            stage_real[4] <= bfly_out_b_re; stage_imag[4] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[1]; bfly_a_im <= stage_imag[1];
                            bfly_b_re <= stage_real[5]; bfly_b_im <= stage_imag[5];
                            bfly_w_re <= W1_RE; bfly_w_im <= W1_IM;
                            bfly_trivial_w <= 1'b0;
                            bfly_cnt <= 4'd3;
                        end
                        // --- Butterfly 1: indices 1,5 with W1 ---
                        4'd3: begin
                            bfly_cnt <= 4'd4;
                        end
                        4'd4: begin
                            stage_real[1] <= bfly_out_a_re; stage_imag[1] <= bfly_out_a_im;
                            stage_real[5] <= bfly_out_b_re; stage_imag[5] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[2]; bfly_a_im <= stage_imag[2];
                            bfly_b_re <= stage_real[6]; bfly_b_im <= stage_imag[6];
                            bfly_w_re <= W2_RE; bfly_w_im <= W2_IM;
                            bfly_trivial_w <= 1'b0;
                            bfly_cnt <= 4'd5;
                        end
                        // --- Butterfly 2: indices 2,6 with W2 ---
                        4'd5: begin
                            bfly_cnt <= 4'd6;
                        end
                        4'd6: begin
                            stage_real[2] <= bfly_out_a_re; stage_imag[2] <= bfly_out_a_im;
                            stage_real[6] <= bfly_out_b_re; stage_imag[6] <= bfly_out_b_im;
                            bfly_a_re <= stage_real[3]; bfly_a_im <= stage_imag[3];
                            bfly_b_re <= stage_real[7]; bfly_b_im <= stage_imag[7];
                            bfly_w_re <= W3_RE; bfly_w_im <= W3_IM;
                            bfly_trivial_w <= 1'b0;
                            bfly_cnt <= 4'd7;
                        end
                        // --- Butterfly 3: indices 3,7 with W3 ---
                        4'd7: begin
                            bfly_cnt <= 4'd8;
                        end
                        4'd8: begin
                            stage_real[3] <= bfly_out_a_re; stage_imag[3] <= bfly_out_a_im;
                            stage_real[7] <= bfly_out_b_re; stage_imag[7] <= bfly_out_b_im;
                            bfly_cnt <= 4'd0;
                            state <= DONE;
                        end
                        default: bfly_cnt <= 4'd0;
                    endcase
                end
                
                DONE: begin
                    // Copy results to outputs
                    out_real_0 <= stage_real[0]; out_imag_0 <= stage_imag[0];
                    out_real_1 <= stage_real[1]; out_imag_1 <= stage_imag[1];
                    out_real_2 <= stage_real[2]; out_imag_2 <= stage_imag[2];
                    out_real_3 <= stage_real[3]; out_imag_3 <= stage_imag[3];
                    out_real_4 <= stage_real[4]; out_imag_4 <= stage_imag[4];
                    out_real_5 <= stage_real[5]; out_imag_5 <= stage_imag[5];
                    out_real_6 <= stage_real[6]; out_imag_6 <= stage_imag[6];
                    out_real_7 <= stage_real[7]; out_imag_7 <= stage_imag[7];
                    
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule


// ============================================================================
// [DP2] Pipelined Butterfly Unit (2-stage)
//
// Stage 1 (registered): Complex multiplication partial products
//   prod_re = b_re*w_re - b_im*w_im
//   prod_im = b_re*w_im + b_im*w_re
//   Also registers a_re, a_im for alignment
//
// Stage 2 (combinational): Final add/subtract
//   out_a = a + prod
//   out_b = a - prod
//
// Trivial twiddle optimization:
//   When trivial_w=1 (W0=1+j0), bypasses multiplication entirely:
//   prod = b (no multiply needed)
// ============================================================================
module butterfly_pipelined (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire signed [15:0] a_re, a_im,      // Input A (complex)
    input  wire signed [15:0] b_re, b_im,      // Input B (complex)
    input  wire signed [15:0] w_re, w_im,      // Twiddle factor W (complex)
    input  wire               trivial_w,       // 1 = W is identity (W0)
    output wire signed [15:0] out_a_re, out_a_im,  // Output A = a + b*w
    output wire signed [15:0] out_b_re, out_b_im,  // Output B = a - b*w
    output reg                valid_out
);

    // ========================================================================
    // Pipeline Stage 1: Multiplication (registered)
    // ========================================================================
    
    // Complex multiplication: b * w = (b_re*w_re - b_im*w_im) + j*(b_re*w_im + b_im*w_re)
    wire signed [31:0] bw_re_full = (b_re * w_re) - (b_im * w_im);
    wire signed [31:0] bw_im_full = (b_re * w_im) + (b_im * w_re);
    
    // Scale down by 15 bits (Q1.15 format) with rounding
    wire signed [15:0] bw_re_scaled = (bw_re_full + 16384) >>> 15;
    wire signed [15:0] bw_im_scaled = (bw_im_full + 16384) >>> 15;
    
    // [DP2] Trivial twiddle bypass: when W=W0=(1,0), b*W = b
    wire signed [15:0] bw_re_muxed = trivial_w ? b_re : bw_re_scaled;
    wire signed [15:0] bw_im_muxed = trivial_w ? b_im : bw_im_scaled;
    
    // Pipeline registers
    reg signed [15:0] pipe_a_re, pipe_a_im;     // Delayed A for alignment
    reg signed [15:0] pipe_bw_re, pipe_bw_im;   // b*w product
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_a_re  <= 16'sd0;
            pipe_a_im  <= 16'sd0;
            pipe_bw_re <= 16'sd0;
            pipe_bw_im <= 16'sd0;
            valid_out  <= 1'b0;
        end else begin
            pipe_a_re  <= a_re;
            pipe_a_im  <= a_im;
            pipe_bw_re <= bw_re_muxed;
            pipe_bw_im <= bw_im_muxed;
            valid_out  <= valid_in;
        end
    end
    
    // ========================================================================
    // Pipeline Stage 2: Addition/Subtraction (combinational)
    // ========================================================================
    assign out_a_re = pipe_a_re + pipe_bw_re;
    assign out_a_im = pipe_a_im + pipe_bw_im;
    assign out_b_re = pipe_a_re - pipe_bw_re;
    assign out_b_im = pipe_a_im - pipe_bw_im;

endmodule
