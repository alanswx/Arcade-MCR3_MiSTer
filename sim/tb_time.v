// Wall-clock duration of the Squawk & Talk command-assembly delay loop,
// using the SAME 40 MHz fractional clock enable squawk_n_talk.sv uses.
//
// Target: the real MC6802 takes 1.294 ms for $FA57 (LDAB #$C1 / DECB / BNE).
// MAME measures the board's two PIA reads 1304 us apart, and the game presents
// the second nibble 1255 us after the first, so this loop MUST exceed ~1139 us
// (measured from the first read) or the second read samples the low nibble
// again and the handler assembles a doubled byte.
`timescale 1ns/1ps

module tb_time;
   parameter integer CPU_HZ = `CPU_HZ;
   localparam integer SYS_HZ = 40_000_000;

   reg clk = 0, rst = 1;
   always #12.5 clk = ~clk;          // 40 MHz

   reg [25:0] cen_acc = 0;
   wire       cen = (cen_acc >= SYS_HZ[25:0]);
   always @(posedge clk) begin
      if (cen) cen_acc <= cen_acc - SYS_HZ[25:0] + CPU_HZ[25:0];
      else     cen_acc <= cen_acc + CPU_HZ[25:0];
   end

   wire        wr;
   wire [15:0] addr;
   wire [ 7:0] dout;
   reg  [ 7:0] mem [0:65535];
   wire [ 7:0] din = mem[addr];

   jt680x u_cpu (
      .rst(rst), .clk(clk), .cen(cen),
      .wr(wr), .addr(addr), .din(din), .dout(dout),
      .ext_halt(1'b0), .ba(),
      .irq(1'b0), .nmi(1'b0),
      .irq_icf(1'b0), .irq_ocf(1'b0), .irq_tof(1'b0),
      .irq_sci(1'b0), .irq_cmf(1'b0), .irq2(1'b0)
   );

   real t_a;
   always @(posedge clk) if (cen) begin
      if (wr && addr == 16'h1234) t_a = $realtime;
      if (wr && addr == 16'h1235) begin
         $display("CPU_HZ = %0d", CPU_HZ);
         $display("  delay loop duration : %0.1f us", ($realtime - t_a) / 1000.0);
         $display("  real MC6802 target  : 1294.1 us");
         $display("  must exceed         : 1139.0 us  (else second read is early)");
         if (($realtime - t_a) / 1000.0 > 1139.0)
            $display("  => PASS");
         else
            $display("  => FAIL, second read lands before the host's high nibble");
         $finish;
      end
   end

   initial begin
      mem[16'hFFFE] = 8'hF0; mem[16'hFFFF] = 8'h00;
      mem[16'hF000] = 8'hB7; mem[16'hF001] = 8'h12; mem[16'hF002] = 8'h34;
      mem[16'hF003] = 8'hC6; mem[16'hF004] = 8'hC1;   // LDAB #$C1
      mem[16'hF005] = 8'h5A;                          // DECB
      mem[16'hF006] = 8'h26; mem[16'hF007] = 8'hFD;   // BNE *-1
      mem[16'hF008] = 8'hB7; mem[16'hF009] = 8'h12; mem[16'hF00A] = 8'h35;
      mem[16'hF00B] = 8'h20; mem[16'hF00C] = 8'hFE;
      repeat (8) @(posedge clk);
      rst = 0;
      #20_000_000;
      $display("TIMEOUT");
      $finish;
   end
endmodule
