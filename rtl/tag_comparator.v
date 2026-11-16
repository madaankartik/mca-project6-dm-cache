// ============================================================================
// tag_comparator.v
// HIT = VALID && (stored tag == requested tag)
// ============================================================================
`timescale 1ns/1ps
module tag_comparator #(
    parameter TAG_W = 22
)(
    input  wire [TAG_W-1:0] tag_req,
    input  wire [TAG_W-1:0] tag_stored,
    input  wire             valid,
    output wire             hit
);
    assign hit = valid && (tag_req == tag_stored);
endmodule
