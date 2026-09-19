`timescale 1ns/1ps
module game_tb;
    reg clk=0, rst_n=0;
    reg [7:0] ui_in=0;
    wire [7:0] uo_out,uio_out,uio_oe;
    tt_um_ezumaex_pacman dut(ui_in,uo_out,8'd0,uio_out,uio_oe,1'b1,clk,rst_n);
    always #20 clk=~clk;
    task tick;
        begin @(negedge clk); force dut.hpos=0; force dut.vpos=480;
            @(posedge clk); #1;
            @(negedge clk); force dut.vpos=481;
        end
    endtask
    task reset;
        begin rst_n=0; repeat(3) @(negedge clk); rst_n=1; end
    endtask
    integer ax,ay;
    initial begin
        reset;
        force dut.hpos=0; force dut.vpos=481;
        if(dut.px!=240 || dut.py!=224 || dut.dots!==~dut.MAZE) $fatal(1,"reset");
        for(ax=0;ax<32;ax=ax+1) for(ay=0;ay<32;ay=ay+1)
            if(dut.circle12(ax,ay)!=(ax*ax+ay*ay<=144)) $fatal(1,"circle");
        ui_in=8; repeat(4) @(negedge clk); tick;
        if(dut.px!=242 || dut.pac_dir!=0) $fatal(1,"right button");
        ui_in=1; repeat(4) @(negedge clk); tick;
        if(dut.py!=222 || dut.pac_dir!=2) $fatal(1,"up button");
        ui_in=4; repeat(4) @(negedge clk);
        dut.px=204; dut.py=128; tick;
        if(dut.px!=204) $fatal(1,"arena boundary");
        dut.px=212; dut.py=160; ui_in=8; repeat(4) @(negedge clk); tick;
        if(dut.px!=212) $fatal(1,"maze collision");
        ui_in=0; reset; repeat(4) @(negedge clk);
        dut.px=208; dut.py=128; tick;
        if(dut.power_timer!=600 || dut.dots[0]!=0) $fatal(1,"power pellet");
        tick; if(dut.power_timer!=599) $fatal(1,"power countdown");
        dut.gx=dut.px; dut.gy=dut.py; tick;
        if(dut.state!=0 || dut.gx!=400 || dut.gy!=256 || dut.power_timer!=0) $fatal(1,"eat ghost");
        dut.gx=dut.px; dut.gy=dut.py; tick;
        if(dut.state!=2) $fatal(1,"lose");
        reset; dut.dots=0; tick;
        if(dut.state!=1) $fatal(1,"win");
        ui_in=16; repeat(6) @(negedge clk);
        if(dut.state!=0 || dut.px!=240 || dut.power_timer!=0) $fatal(1,"software restart");
        $display("PASS: movement, boundaries, walls, power pellet/timer, ghost collision, win, resets, exact circle");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
