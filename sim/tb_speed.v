// How many `cen` pulses does jt680x take per 6800 E cycle?
//
// This decides whether the Squawk & Talk 6802 runs at the right speed. The
// board's IRQ handler reads the command port, spins LDAB #$C1 / DECB / BNE,
// then reads again. On a real 6802 that gap is ~1300us; if our CPU is 4x fast
// it is ~325us and the second read lands before the game has presented the
// high nibble.
//
// Program: marker write, the exact delay loop, marker write. Count cen pulses
// between the two markers. cen is asserted every clock, so pulses == clocks.
//   ~1158  -> cen is the E (bus cycle) rate
//   ~4632  -> cen is the crystal rate, core divides by 4 internally
`timescale 1ns/1ps

module tb_speed;
   reg clk = 0, rst = 1;
   wire cen = 1'b1;
   wire        wr;
   wire [15:0] addr;
   wire [ 7:0] dout;
   reg  [ 7:0] mem [0:65535];

   always #5 clk = ~clk;

   wire [7:0] din = mem[addr];

   jt680x u_cpu (
      .rst(rst), .clk(clk), .cen(cen),
      .wr(wr), .addr(addr), .din(din), .dout(dout),
      .ext_halt(1'b0), .ba(),
      .irq(1'b0), .nmi(1'b0),
      .irq_icf(1'b0), .irq_ocf(1'b0), .irq_tof(1'b0),
      .irq_sci(1'b0), .irq_cmf(1'b0), .irq2(1'b0)
   );

   integer count = 0;
   reg running = 0, done = 0;

   always @(posedge clk) if (cen) begin
      if (running && !done) count = count + 1;
      if (wr && addr == 16'h1234) begin
         running <= 1;
         $display("marker A (loop start) at %0t", $time);
      end
      if (wr && addr == 16'h1235) begin
         done <= 1;
         $display("marker B (loop end)   at %0t", $time);
         $display("");
         $display("cen pulses across LDAB #$C1 / DECB / BNE : %0d", count);
         $display("  6800 E cycles for that loop            : ~1158");
         $display("  ratio cen-per-E-cycle                  : %0d", count / 1158);
         if (count < 2000)
            $display("  => cen IS the E rate. Feeding 3.579545MHz makes E 4x TOO FAST.");
         else
            $display("  => cen is the CRYSTAL rate (core divides by 4). E is correct.");
         $finish;
      end
   end

   initial begin
      // reset vector -> $F000
      mem[16'hFFFE] = 8'hF0; mem[16'hFFFF] = 8'h00;
      // $F000: STAA $1234      marker A
      mem[16'hF000] = 8'hB7; mem[16'hF001] = 8'h12; mem[16'hF002] = 8'h34;
      // $F003: LDAB #$C1
      mem[16'hF003] = 8'hC6; mem[16'hF004] = 8'hC1;
      // $F005: DECB
      mem[16'hF005] = 8'h5A;
      // $F006: BNE $F005      (rel = -3)
      mem[16'hF006] = 8'h26; mem[16'hF007] = 8'hFD;
      // $F008: STAA $1235      marker B
      mem[16'hF008] = 8'hB7; mem[16'hF009] = 8'h12; mem[16'hF00A] = 8'h35;
      // $F00B: BRA *
      mem[16'hF00B] = 8'h20; mem[16'hF00C] = 8'hFE;

      repeat (8) @(posedge clk);
      rst = 0;
      #4_000_000;
      $display("TIMEOUT - no marker B; count=%0d", count);
      $finish;
   end
endmodule
