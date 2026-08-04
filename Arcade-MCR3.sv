//============================================================================
//  Arcade: Tapper
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================


module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;


assign VGA_F1    = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign USER_OUT  = '1;
// On dotrone the user LED doubles as the Squawk & Talk activity probe: it
// lights for ~0.17 s whenever the game issues a new non-zero sound command on
// OP4. That answers "is the game actually talking to the speech board?" from
// across the bench, without a SignalTap build. Unchanged for every other set.
assign LED_USER  = ioctl_download | (mod_dotrone_any & snt_active);
assign LED_DISK  = 0;
assign LED_POWER = 0;

wire [1:0] ar = status[15:14];

assign VIDEO_ARX = (!ar) ? ((status[2] | landscape) ? 8'd4 : 8'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2] | landscape) ? 8'd3 : 8'd4) : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.MCR3;;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H2H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"D3OD,Deinterlacer Hi-Res,Off,On;",
	"O6,Audio,Mono,Stereo;",
	"O7,Flip Screen,Off,On;",
	"O8,S&T Probe,Off,On;",
	"O9,Backdrop,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Fire A,Fire B,Fire C,Fire D,Rotate CW,Rotate CCW,Start1,Start2,Coin;",
	"jn,A,B,X,Y,R,L,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire clk_mem = clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire        video_rotated;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

wire [31:0] joy1, joy2;
wire [31:0] joy = joy1 | joy2;
wire [10:0] ps2_key;
wire  [8:0] sp1, sp2; 

wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_menumask({|status[5:3],landscape,mod_dotron_any,direct_video}),
	.forced_scandoubler(forced_scandoubler),
   .video_rotated(video_rotated),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),
	
	.joystick_0(joy1),
	.joystick_1(joy2),

	.ps2_key(ps2_key),

	.spinner_0(sp1),
	.spinner_1(sp2)
);

// ---------------------------------------------------------------------------
// RAW PS/2 KEYBOARD DECODE for coin and start.
//
// Why this exists: coin/start normally arrive as joy[12]/joy[10]/joy[11], i.e.
// through MiSTer's JOYSTICK MAPPING layer. Driving that layer remotely (mrext's
// POST /api/controls/keyboard-raw/{code}, or a hand-rolled uinput keyboard)
// proved unreliable -- CREDITS stayed 0 while every call returned 200. ps2_key
// is a different path: hps_io hands the core raw scancodes regardless of any
// joystick mapping, which is how the computer cores get typing. Decoding here
// routes around the layer that was failing.
//
// The keys are the SAME ones a cabinet keyboard uses (5 = coin, 1/2 = start),
// and these are OR'd with the joystick bits, so nothing changes for a human at
// the bench -- pressing 5 simply now works through both paths.
//
// ps2_key = { toggle, pressed, extended, code[7:0] }; bit 10 flips on every
// event, so compare it against its previous value rather than edge-detecting
// `pressed`.
// ---------------------------------------------------------------------------
reg kbd_coin1 = 0, kbd_start1 = 0, kbd_start2 = 0;
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	if (old_state != ps2_key[10]) begin
		case (ps2_key[7:0])
			8'h2E: kbd_coin1  <= ps2_key[9];   // '5'
			8'h16: kbd_start1 <= ps2_key[9];   // '1'
			8'h1E: kbd_start2 <= ps2_key[9];   // '2'
			default: ;
		endcase
	end
end

wire rom_download = ioctl_download && !ioctl_index;

wire [15:0] rom_addr;
wire  [7:0] rom_do;
wire [13:0] snd_addr;
wire [15:0] snd_do;
wire [14:0] sp_addr;
wire [31:0] sp_do;

// ROM structure:
// 00000 - 0DFFF  - Main ROM (8 bit)
// 0E000 - 11FFF - Super Sound board ROM (8 bit)
// 12000 - 31FFF - Sprite ROMs (32 bit)
// 32000 - 39FFF - BG ROMS
// 3A000 - 3DFFF - Squawk & Talk board ROM (8 bit, dotrone only) -- 16 KB
//                 mapping 1:1 onto the 6802's $8000-$BFFF window. The first
//                 4 KB is the unpopulated U2 socket and the MRA zero-fills it,
//                 so pre.u3/u4/u5 land at $9000/$A000/$B000 as in MAME.
//                 Absent from every other set's MRA, which simply stop at
//                 0x39FFF.

//wire [24:0] rom_ioctl_addr = ~ioctl_addr[16] ? ioctl_addr : // 8 bit ROMs
//                             {ioctl_addr[24:16], ioctl_addr[15], ioctl_addr[13:0], ioctl_addr[14]}; // 16 bit ROM

wire [24:0] sp_ioctl_addr = ioctl_addr - 17'h12000; //SP ROM offset: 0x12000
wire [24:0] dl_addr = ioctl_addr - 18'h32000; //background offset

reg port1_req, port2_req;
sdram sdram
(
	.*,
	.init_n        ( pll_locked   ),
	.clk           ( clk_mem      ),

	// port1 used for main + sound CPUs
	.port1_req     ( port1_req    ),
	.port1_ack     ( ),
	.port1_a       ( ioctl_addr[23:1] ),
	.port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
	.port1_we      ( rom_download ),
	.port1_d       ( {ioctl_dout, ioctl_dout} ),
	.port1_q       ( ),

	.cpu1_addr     ( rom_download ? 16'hffff : (16'h7000 + snd_addr[13:1]) ),
	.cpu1_q        ( snd_do ),
	.cpu2_addr     ( ),
	.cpu2_q        ( ),
	.cpu3_addr     ( ),
	.cpu3_q        ( ),

	// port2 for sprite graphics
	.port2_req     ( port2_req ),
	.port2_ack     ( ),
	.port2_a       ( {sp_ioctl_addr[18:17], sp_ioctl_addr[14:0], sp_ioctl_addr[16]} ), // merge sprite roms to 32-bit wide words
	.port2_ds      ( {sp_ioctl_addr[15], ~sp_ioctl_addr[15]} ),
	.port2_we      ( rom_download ),
	.port2_d       ( {ioctl_dout, ioctl_dout} ),
	.port2_q       ( ),

	.sp_addr       ( rom_download ? 15'h7fff : sp_addr ),
	.sp_q          ( sp_do )
);

dpram #(8,16) cpu_rom
(
	.clk_a(clk_sys),
	.we_a(ioctl_wr && rom_download && !ioctl_addr[24:16]),
	.addr_a(ioctl_addr[15:0]),
	.d_a(ioctl_dout),

	.clk_b(clk_sys),
	.addr_b(rom_addr),
	.q_b(rom_do)
);

// Squawk & Talk board ROM, 0x3A000-0x3DFFF. Only dotrone's MRA supplies it;
// for every other set this RAM simply stays blank and the board is inert.
//
// 0x3A000 is NOT 16 KB aligned, so the region base must be SUBTRACTED rather
// than masked off -- same pattern as sp_ioctl_addr and dl_addr above. Masking
// with ioctl_addr[13:0] would rotate the ROM by 0x2000 inside the RAM, which
// puts the reset vector in the wrong place and is invisible until the 6802
// exists to fetch it.
wire [24:0] snt_ioctl_addr = ioctl_addr - 25'h3A000;
wire        snt_rom_we = ioctl_wr && rom_download
                         && (ioctl_addr >= 25'h3A000) && (ioctl_addr < 25'h3E000);
wire [13:0] snt_rom_addr;
wire  [7:0] snt_rom_do;

// Definitive check of the S&T download AND the MRA layout: capture the two
// bytes the 6802 will fetch as its RESET vector ($BFFE/$BFFF, which is
// download offset 0x3DFFE/0x3DFFF) and compare against the value read straight
// out of pre.u5 offline: $F983.
//
// `rom_nonzero` in the probe does NOT establish this -- the vector fetch alone
// sets that bit even if every byte is at the wrong offset. If the MRA's
// <part repeat="4096"> zero-fill were dropped, everything would shift 4 KB and
// this check is what catches it.
reg [7:0] snt_vec_hi = 0, snt_vec_lo = 0;
always @(posedge clk_sys) begin
	if (ioctl_wr && rom_download && ioctl_addr == 25'h3DFFE) snt_vec_hi <= ioctl_dout;
	if (ioctl_wr && rom_download && ioctl_addr == 25'h3DFFF) snt_vec_lo <= ioctl_dout;
end
wire snt_rom_ok = (snt_vec_hi == 8'hF9) && (snt_vec_lo == 8'h83);

dpram #(8,14) snt_rom
(
	.clk_a(clk_sys),
	.we_a(snt_rom_we),
	.addr_a(snt_ioctl_addr[13:0]),
	.d_a(ioctl_dout),

	.clk_b(clk_sys),
	.addr_b(snt_rom_addr),
	.q_b(snt_rom_do)
);

// ROM download controller
always @(posedge clk_sys) begin
	if (rom_download) begin
		if (ioctl_wr && rom_download) begin
			port1_req <= ~port1_req;
			port2_req <= ~port2_req;
		end
	end
end

// reset signal generation
reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg ioctl_downlD;
	reg [15:0] reset_count;
	ioctl_downlD <= rom_download;

	// generate a second reset signal - needed for some reason
	if (status[0] | buttons[1] | ~rom_loaded) reset_count <= 16'hffff;
	else if (reset_count != 0) reset_count <= reset_count - 1'd1;

	if (ioctl_downlD & ~rom_download) rom_loaded <= 1;
	reset <= status[0] | buttons[1] | rom_download | ~rom_loaded | (reset_count == 16'h0001);
end

wire service = sw[1][0];

// Generic controls - make a module from this?

// ...| kbd_* : the raw PS/2 decode above, so coin/start also work when the
// joystick mapping layer is not delivering (see the decoder's comment).
wire m_start1  = joy[10] | kbd_start1;
wire m_start2  = joy[11] | kbd_start2;
wire m_coin1   = joy[12] | kbd_coin1
               | (mod_dotron_any & (joy[10] | joy[11] | kbd_start1 | kbd_start2));

wire m_right1  = joy1[0];
wire m_left1   = joy1[1];
wire m_down1   = joy1[2];
wire m_up1     = joy1[3];
wire m_fire1a  = joy1[4];
wire m_fire1b  = joy1[5];
wire m_fire1c  = joy1[6];
wire m_fire1d  = joy1[7];
wire m_rcw1    = joy1[8];
wire m_rccw1   = joy1[9];
wire m_spccw1  = joy1[30];
wire m_spcw1   = joy1[31];

wire m_right2  = joy2[0];
wire m_left2   = joy2[1];
wire m_down2   = joy2[2];
wire m_up2     = joy2[3];
wire m_fire2a  = joy2[4];
wire m_fire2b  = joy2[5];
wire m_fire2c  = joy2[6];
wire m_fire2d  = joy2[7];
wire m_rcw2    = joy2[8];
wire m_rccw2   = joy2[9];
wire m_spccw2  = joy2[30];
wire m_spcw2   = joy2[31];

wire m_right   = m_right1 | m_right2;
wire m_left    = m_left1  | m_left2; 
wire m_down    = m_down1  | m_down2; 
wire m_up      = m_up1    | m_up2;   
wire m_fire_a  = m_fire1a | m_fire2a;
wire m_fire_b  = m_fire1b | m_fire2b;
wire m_fire_c  = m_fire1c | m_fire2c;
wire m_fire_d  = m_fire1d | m_fire2d;
wire m_rcw     = m_rcw1   | m_rcw2;
wire m_rccw    = m_rccw1  | m_rccw2;
wire m_spccw   = m_spccw1 | m_spccw2;
wire m_spcw    = m_spcw1  | m_spcw2;

reg [8:0] sp;
always @(posedge clk_sys) begin
	reg [8:0] old_sp1, old_sp2;
	reg       sp_sel = 0;

	old_sp1 <= sp1;
	old_sp2 <= sp2;
	
	if(old_sp1 != sp1) sp_sel <= 0;
	if(old_sp2 != sp2) sp_sel <= 1;

	sp <= sp_sel ? sp2 : sp1;
end

reg  [7:0] input_0;
reg  [7:0] input_1;
reg  [7:0] input_2;
reg  [7:0] input_3;
reg  [7:0] input_4;
wire [7:0] output_4;

reg mod_tapper = 0;
reg mod_timber = 0;
reg mod_dotron = 0;
reg mod_journey= 0;
reg mod_dotrone= 0;
reg mod_dotrone_up = 0;
always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

	mod_tapper <= ( mod == 0 );
	mod_timber <= ( mod == 1 );
	mod_dotron <= ( mod == 2 );
	mod_journey<= ( mod == 3 );
	mod_dotrone<= ( mod == 4 );	// Discs of Tron (Environmental) - adds Squawk & Talk
	// mod 5 is a BRING-UP CONTROL, not a real machine: the Environmental ROM
	// set with the cabinet strap forced to Upright. It exists so the "is the
	// game talking to the speech board?" probe can be falsified -- run mod 4
	// and mod 5 back to back, and the probe must light for one and stay dark
	// for the other. Without that, a lit probe only proves the probe is lit.
	mod_dotrone_up <= ( mod == 5 );
end

// Both Discs of Tron cabinets share video orientation, coin wiring and the
// control panel. They differ ONLY in the IP2 bit 7 cabinet strap (below), the
// CPU/SSIO ROM revision, and the presence of the Squawk & Talk speech board.
wire mod_dotron_any = mod_dotron | mod_dotrone | mod_dotrone_up;
// Everything that follows the Environmental ROM set, strap aside.
wire mod_dotrone_any = mod_dotrone | mod_dotrone_up;

// load the DIPS
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

reg landscape;

// Game specific sound board/DIP/input settings
always @(*) begin

	landscape = 1; 
	input_0 = 8'hff;
	input_1 = 8'hff;
	input_2 = 8'hff;
	input_3 = sw[0];
	input_4 = 8'hff;

	if (mod_tapper) begin
		input_0 = ~{ service, 3'b000, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 3'b000, m_fire_a, m_up, m_down, m_left, m_right };
		input_2 = ~{ 3'b000, m_fire_a, m_up, m_down, m_left, m_right };
	end
	else if (mod_timber) begin
		input_0 = ~{ service, 3'b000, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 2'b00, m_fire1a, m_fire1b, m_up1, m_down1, m_left1, m_right1 };
		input_2 = ~{ 2'b00, m_fire2a, m_fire2b, m_up2, m_down2, m_left2, m_right2 };
	end
	else if (mod_dotron_any) begin
		input_0 = ~{ service, 2'b00, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 1'b0, spin_tron[7:1] };
		// IP2 bit 7 is the CABINET strap, and it is not cosmetic: the game reads
		// it to decide whether it is an Environmental cabinet. Active low, so
		// 0 = Environmental, 1 = Upright (MAME dotron/dotrone INPUT_PORTS,
		// PORT_DIPNAME Cabinet). Get this wrong on dotrone and the Environmental
		// ROMs run in upright mode - it boots and plays, but never speaks.
		input_2 = ~{ mod_dotrone, m_fire_b, m_fire_c, m_fire_d, m_down, m_up, m_right, m_left };
	end
	else if (mod_journey) begin
		landscape = 0;
		input_0 = ~{ service, 2'b00, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 4'b0000, m_down, m_up, m_right, m_left };
		input_2 = ~{ 3'b000, m_fire_a, m_down, m_up, m_right, m_left };
	end
end

wire [7:0] spin_tron;
spinner #(10,0,5) spinner_tr
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_rccw | m_spccw),
	.plus(m_rcw | m_spcw),
	.strobe(vs),
	.spin_in(sp),
	.spin_out(spin_tron)
);

wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

wire hires = status[13] && !status[5:3];

reg  ce_pix;
always @(posedge clk_80M) begin
	reg [2:0] div;
	
	div <= div + 1'd1;
	ce_pix <= hires ? !div[1:0] : !div;
end

// Screen flip, hoisted above the backdrop block below which mirrors the
// backdrop address with it. Declared here rather than beside the other video
// wires because a use-before-declaration is a duplicate-net error in SV -- and
// on Gowin it silently becomes an implicit 1-bit wire instead, which is how
// jt680x's jsr_sel got truncated during the Tang port.
wire core_flip = status[7];

// ===========================================================================
// CABINET BACKDROP (status[9], "Backdrop" in the OSD)
//
// Discs of Tron -- both the upright and the Environmental -- puts a backlit
// painted cityscape behind a HALF-SILVERED MIRROR and superimposes the monitor
// image on it. You see the artwork wherever the tube is black. That is what
// this reproduces: the backdrop shows through every black game pixel, which is
// the same hook the S&T probe tint uses below.
//
// The artwork is hardbaked into the MRA as rom index 2 (see
// tools/make_backdrop.py) -- 512x240, one 16-bit little-endian word per pixel
// carrying 9-bit 3:3:3 colour. Nothing ships alongside the MRA. Multi-megabyte
// inline MRA payloads are an established MiSTer pattern, not an invention:
// Cosmic Alien.mra is 3.4 MB of inline hex for its WAV samples.
//
// THE FLIP IS THE WHOLE TRICK HERE. video_hflip/video_vflip are inputs to
// mcr3.vhd and flip its RASTER COUNTERS (rtl/mcr3.vhd:508-511), so the RGB
// leaving the core is ALREADY flipped -- Discs of Tron runs mirrored because
// the real cabinet has a mirror. A backdrop composited after the core without
// the same treatment would sit still while the game mirrored around it.
// Flipping the backdrop's ADDRESS is equivalent to flipping the image, so the
// counters below are mirrored with the very same signals the core is given.
// Screen ROTATION needs nothing: MiSTer rotates downstream of this RGB stream,
// so anything composited in rotates with the game for free.
// ===========================================================================
wire bd_dl = ioctl_download && (ioctl_index == 8'd2);

// Download: the MRA delivers two bytes per pixel, low byte first. Pair them
// and keep only the 9 bits the video path can actually show.
reg  [16:0] bd_wr_addr = 0;
reg   [7:0] bd_lo = 0;
reg         bd_phase = 0;
reg         bd_we = 0;
reg   [8:0] bd_wr_data = 0;
always @(posedge clk_sys) begin
	bd_we <= 1'b0;
	if (!bd_dl) begin
		bd_phase   <= 1'b0;
		bd_wr_addr <= 17'd0;
	end
	else if (ioctl_wr) begin
		bd_phase <= ~bd_phase;
		if (!bd_phase) bd_lo <= ioctl_dout;
		else begin
			bd_wr_data <= {ioctl_dout[0], bd_lo};   // 9-bit 3:3:3
			bd_we      <= 1'b1;
		end
	end
	if (bd_we) bd_wr_addr <= bd_wr_addr + 1'd1;
end

// 512 x 240 x 9 bits = 1,105,920 bits = 108 M10K. Sized EXACTLY rather than
// rounded up to a power of two, which would waste ~8 blocks for nothing.
(* ramstyle = "M10K" *) reg [8:0] bd_ram[0:122879];
always @(posedge clk_sys) if (bd_we) bd_ram[bd_wr_addr] <= bd_wr_data;

// Active-pixel counters taken from the core's own blanking, so they cannot
// drift out of step with the picture.
reg  [9:0] bd_x = 0;
reg  [9:0] bd_y = 0;
reg        hb_d = 0, vb_d = 0;
always @(posedge clk_80M) begin
	if (ce_pix) begin
		hb_d <= hblank;
		vb_d <= vblank;
		if (hblank) bd_x <= 10'd0;
		else if (!(&bd_x)) bd_x <= bd_x + 1'd1;
		if (vblank) bd_y <= 10'd0;
		else if (hblank && !hb_d && !(&bd_y)) bd_y <= bd_y + 1'd1;  // new line
	end
end

// Mirror the ADDRESS with the same signals the core's counters get. In Hi-Res
// the core runs 480 lines, so mirror on 479 and then halve -- the stored image
// is 240 lines and each is shown twice.
wire        bd_hflip = mod_dotron_any ^ core_flip;
wire        bd_vflip = core_flip;
wire  [9:0] bd_ax = bd_hflip ? (10'd511 - bd_x) : bd_x;
wire  [9:0] bd_ay_full = hires ? (bd_vflip ? (10'd479 - bd_y) : bd_y)
                               : (bd_vflip ? (10'd239 - bd_y) : bd_y);
wire  [8:0] bd_row = hires ? bd_ay_full[9:1] : bd_ay_full[8:0];

reg [8:0] bd_pix;
always @(posedge clk_80M) if (ce_pix) bd_pix <= bd_ram[{bd_row, bd_ax[8:0]}];

// Show it only where the game is black -- that is the mirror.
wire bd_en   = status[9] && mod_dotron_any;
wire bd_here = bd_en && ~|{r, g, b};

// Squawk & Talk bring-up probe (status[8], "S&T Probe" in the OSD).
//
// `snt_seen` is STICKY: set the first time the game issues a non-zero sound
// command on OP4, and held until reset. Sticky rather than a pulse so that a
// SINGLE screenshot answers "is the game talking to the speech board?" -- an
// LED or a 0.17 s flash needs eyes on the bench and lucky timing, whereas this
// survives to whenever the screenshot happens to be taken.
//
// It also confirms the Environmental cabinet strap indirectly: an upright
// dotron issues no S&T commands at all, so a lit probe means IP2 bit 7 was
// read as Environmental.
//
// Default ON (option reads On,Off so the power-on status of 0 enables it):
// this core has no saved config on the bench machine, so a default-off probe
// would need OSD fiddling over a remote link to be any use.
//
// It tints ONLY pixels that are already black, so the backdrop goes dark blue
// while every sprite, tile and glyph stays exactly as it was. A full-screen
// tint would answer the question but destroy the ability to see the game at
// the same time -- and this needs no pixel counters either way.
// Three INDEPENDENT sticky facts encoded as the backdrop colour, so one
// screenshot separates "the game never asked" from "the board never answered".
// Only already-black pixels are touched, so the game stays fully visible.
//
//   RED   = snt_cpu_run     : 6802 address bus has changed 255 times (running)
//   GREEN = snt_dac_written : 6802 has written the AD558 (executing board code)
//   BLUE  = snt_seen        : game has strobed OP4 bit 4 twice (commanding us)
//
// So: black = nothing at all; red = CPU runs but idle; yellow = CPU running
// board code with no host traffic; white = everything working.
// Probe now defaults OFF: the full chain reads GREEN=7 / RED=7, so it has
// done its job and a tinted backdrop just gets in the way of playing.
// Turn it back on from the OSD ("S&T Probe") if a regression needs chasing.
wire snt_probe = status[8] & mod_dotrone_any;   // default OFF; OSD toggles
wire snt_black = ~|{r, g, b};

// Backdrop first, probe tint on top of the result: the probe is a debug aid
// (default off) and must still win when it is switched on.
wire [2:0] bd_r = bd_here ? bd_pix[8:6] : r;
wire [2:0] bd_g = bd_here ? bd_pix[5:3] : g;
wire [2:0] bd_b = bd_here ? bd_pix[2:0] : b;
wire [2:0] probe_r = (snt_probe & snt_black) ? snt_cpu_run : bd_r;
// GREEN is a 3-BIT PROGRESS CODE rendered as intensity, not a flag:
//   1 = 6802 read PIA2   2 = it was interrupted   4 = it drove TMS /WS
// so 0=nothing, 3=interrupted+servicing, 7=full chain. Distinct green
// levels (0/36/73/109/146/182/219/255 after 3->8 bit expansion) are easy
// to read back out of a screenshot.
wire [2:0] probe_g = (snt_probe & snt_black) ? snt_progress : bd_g;
// BLUE is a 3-bit code as well now:
//   bit0 host has strobed OP4 bit 4
//   bit1 the downloaded RESET vector is exactly $F983 (ROM layout is correct)
//   bit2 the CPU has addressed 0080-009F under a LOOSE decode that ignores the
//        mirror mask entirely. If bit2 lights while GREEN bit0 stays dark, my
//        0xB090 mirror mask is wrong -- that separates "decode bug" from
//        "the CPU never goes there" in one reading.
wire [2:0] probe_b = (snt_probe & snt_black) ? {snt_pia_loose, snt_tms_nz, snt_seen} : bd_b;  // bit1 now = TMS produced audio

arcade_video #(512,9) arcade_video
(
	.*,
	.ce_pix(ce_pix),
	.clk_video(clk_80M),
	.RGB_in({probe_r,probe_g,probe_b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

wire no_rotate = status[2] | direct_video | landscape;
wire rotate_ccw = 0;
wire flip       = 0;
// core_flip is declared ABOVE, before the backdrop block that needs it.

assign {FB_PAL_CLK, FB_FORCE_BLANK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = '0;
ddram ddram (.*, .s_wr(0),.s_din(0),.s_be(0));

wire [15:0] audio_l, audio_r;

// Squawk & Talk speech board (dotrone only). Step-2 shell: snt_audio is hard 0,
// so the sums below are no-ops and every other set is bit-identical to before.
//
// NOTE for step 5: the core's audio is UNSIGNED (AUDIO_S is only asserted for
// Journey, whose wave player is signed), whereas the TMS5200 output is SIGNED
// and the AD558 DAC is unsigned. Settle on one convention inside
// squawk_n_talk before widening this sum, and revisit AUDIO_S for dotrone.
wire signed [15:0] snt_audio;
wire        snt_active, snt_seen, snt_dac_written;
wire  [2:0] snt_cpu_run;
wire        snt_pia_loose, snt_tms_nz;
wire  [2:0] snt_progress;

squawk_n_talk squawk_n_talk
(
	.clk(clk_sys),
	.reset(reset),
	.sound_select(output_4[3:0]),
	.sound_int(output_4[4]),
	.dbg_in2(input_2),
	.dbg_op4(output_4),
	.rom_addr(snt_rom_addr),
	.rom_do(snt_rom_do),
	.audio_out(snt_audio),
	.active(snt_active),
	.seen(snt_seen),
	.cpu_run(snt_cpu_run),
	.progress(snt_progress),
	.pia_loose(snt_pia_loose),
	.tms_audio_nz(snt_tms_nz),
	.dac_written(snt_dac_written),
	.dbg_dac(),
	.dbg_cpu_addr(),
	.dbg_tms_wsn(),
	.dbg_tms_rsn()
);

// The core's audio is UNSIGNED (AUDIO_S is only asserted for Journey) while
// the S&T board's is a SIGNED swing about zero, so this is an unsigned base
// plus a signed offset, clamped at BOTH ends - underflow to 0, overflow to
// full scale. Clamping only the top would wrap loud negative excursions round
// to full volume, which is exactly the sort of thing that sounds like a broken
// speech core rather than a broken mixer.
wire signed [17:0] snt_mix_l = $signed({2'b00, audio_l}) + $signed({{2{snt_audio[15]}}, snt_audio});
wire signed [17:0] snt_mix_r = $signed({2'b00, audio_r}) + $signed({{2{snt_audio[15]}}, snt_audio});
wire [15:0] snt_aud_l = snt_mix_l[17] ? 16'h0000 : (snt_mix_l[16] ? 16'hffff : snt_mix_l[15:0]);
wire [15:0] snt_aud_r = snt_mix_r[17] ? 16'h0000 : (snt_mix_r[16] ? 16'hffff : snt_mix_r[15:0]);

assign AUDIO_S = mod_journey;
assign AUDIO_L = mod_journey ? j_aud_l : (mod_dotrone_any ? snt_aud_l : audio_l);
assign AUDIO_R = mod_journey ? j_aud_r : (mod_dotrone_any ? snt_aud_r : audio_r);

mcr3 mcr3
(
	.clock_40(clk_sys),
	.reset(reset),
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.video_hs(hs),
	.video_vs(vs),
	.video_hflip(mod_dotron_any ^ core_flip),
	.video_vflip(core_flip),
	.tv15Khz_mode(~hires),
	.separate_audio(status[6]),
	.audio_out_l(audio_l),
	.audio_out_r(audio_r),
	.input_0(input_0),
	.input_1(input_1),
	.input_2(input_2),
	.input_3(input_3),
	.input_4(input_4),
	.output_4(output_4),	
	.mcr2p5(mod_journey),
	.cpu_rom_addr(rom_addr),
	.cpu_rom_do(rom_do),
	.snd_rom_addr(snd_addr),
	.snd_rom_do(snd_addr[0] ? snd_do[15:8] : snd_do[7:0]),
	.sp_addr(sp_addr),
	.sp_graphx32_do(sp_do),
	
	.dl_addr(dl_addr),
	.dl_wr(ioctl_wr & rom_download),
	.dl_data(ioctl_dout),
	.dl_nvram_wr(ioctl_wr & (ioctl_index=='d4)), 
	.dl_din(ioctl_din),
	.dl_nvram(ioctl_index=='d4)
);


////////////////////////////  WAV PLAYER  ///////////////////////////////////
//
//

wire wav_load = ioctl_download && (ioctl_index == 2);

wire [63:0] s_dout;
wire [24:0] s_addr = wav_addr[27:3];
wire        s_ack;
reg         s_rd;
reg         wav_data_ready;

always @(posedge clk_sys) begin
	reg old_wav_rd;
	reg old_ack;

	old_ack <= s_ack;
	if((old_ack ^ s_ack) | reset) wav_data_ready <= 1;

	old_wav_rd <= wav_rd;
	if(~old_wav_rd & wav_rd) begin
		s_rd <= ~s_rd;
		wav_data_ready <= 0;
	end
end

reg pause;
reg wav_loaded = 0;
always @(posedge clk_sys) begin
	reg old_load;
	
	old_load <= wav_load;
	if(old_load & ~wav_load) wav_loaded <= 1;
	
	pause <= ~output_4[0];
end

wire [27:0] wav_addr;
wire  [7:0] wav_data = s_dout[(wav_addr[2:0]*8) +:8];
wire        wav_rd;
wire [15:0] pcm_audio;

wave_sound #(40000000) wave_sound
(
	.I_CLK(clk_sys),
	.I_RST(reset | ~wav_loaded),

	.I_BASE_ADDR(0),
	.I_LOOP(1),
	.I_PAUSE(pause),

	.O_ADDR(wav_addr),        // output address to wave ROM
	.O_READ(wav_rd),          // read a byte
	.I_DATA(wav_data),        // Data coming back from wave ROM
	.I_READY(wav_data_ready), // read a byte

	.O_PCM(pcm_audio)
);

wire [16:0] j_pre_aud_l = ({{2{pcm_audio[15]}},pcm_audio[15:1]} + {1'b0,audio_l});
wire [16:0] j_pre_aud_r = ({{2{pcm_audio[15]}},pcm_audio[15:1]} + {1'b0,audio_r});

reg [15:0] j_aud_l,j_aud_r;
always @(posedge clk_sys) begin
	if(^j_pre_aud_l[16:15]) j_aud_l <= {15{j_pre_aud_l[16]}};
	else j_aud_l <= j_pre_aud_l[15:0];

	if(^j_pre_aud_r[16:15]) j_aud_r <= {15{j_pre_aud_r[16]}};
	else j_aud_r <= j_pre_aud_r[15:0];
end

endmodule
