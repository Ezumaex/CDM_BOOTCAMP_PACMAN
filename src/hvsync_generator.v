// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module hvsync_generator (
    input wire clk, reset,
    output wire hsync, vsync, display_on,
    output reg [9:0] hpos, vpos
);
    // 640x480 at 59.94 Hz with a 25.175 MHz pixel clock.
    always @(posedge clk) begin
        if (reset) begin
            hpos <= 10'd0;
            vpos <= 10'd0;
        end else if (hpos == 10'd799) begin
            hpos <= 10'd0;
            vpos <= vpos == 10'd524 ? 10'd0 : vpos + 10'd1;
        end else hpos <= hpos + 10'd1;
    end
    assign hsync = !(hpos >= 10'd656 && hpos < 10'd752);
    assign vsync = !(vpos >= 10'd490 && vpos < 10'd492);
    assign display_on = hpos < 10'd640 && vpos < 10'd480;
endmodule
`default_nettype wire
