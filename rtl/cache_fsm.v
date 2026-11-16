// ============================================================================
// cache_fsm.v -- Cache controller finite-state machine
//
// Policy: WRITE-THROUGH, NO-WRITE-ALLOCATE (read-allocate only)
//
//   IDLE      : wait for cpu_req, latch the request
//   COMPARE   : tag lookup
//                 read  hit  -> return data, cpu_ready        -> IDLE
//                 read  miss -> request block from memory     -> ALLOCATE
//                 write hit  -> update cached word            -> WRITE_MEM
//                 write miss -> (no allocate)                 -> WRITE_MEM
//   ALLOCATE  : wait for main memory block; on mem_ready write data/tag/valid
//               and go back to COMPARE (which now hits)
//   WRITE_MEM : write the word through to main memory; on mem_ready -> IDLE
//
// The controller is a Moore/Mealy mix: control strobes depend on state + hit.
// ============================================================================
`timescale 1ns/1ps
module cache_fsm (
    input  wire       clk,
    input  wire       rst,
    // CPU side
    input  wire       cpu_req,       // request pulse/level seen in IDLE
    input  wire       req_we,        // latched: 1 = store, 0 = load
    output reg        cpu_ready,     // response valid (1 cycle)
    output wire       resp_hit,      // was this request a cache hit?
    // datapath status
    input  wire       hit,           // from tag comparator
    // datapath control
    output reg        latch_req,     // capture cpu_addr/cpu_wdata/cpu_we
    output reg        tag_we,
    output reg        valid_we,
    output reg        data_block_we,
    output reg        data_word_we,
    output wire       first_lookup,  // 1st COMPARE of a request (for statistics)
    // memory side
    output reg        mem_req,
    output reg        mem_we,
    input  wire       mem_ready,
    // debug
    output wire [1:0] state_o
);
    localparam [1:0] S_IDLE      = 2'd0,
                     S_COMPARE   = 2'd1,
                     S_ALLOCATE  = 2'd2,
                     S_WRITE_MEM = 2'd3;

    reg [1:0] state, next_state;
    reg       refilled;      // set after a refill so the re-lookup is not counted twice
    reg       hit_lat;       // remembers hit/miss of the first lookup

    assign state_o      = state;
    assign first_lookup = (state == S_COMPARE) && !refilled;
    assign resp_hit     = first_lookup ? hit : hit_lat;

    // ---------------- state register ----------------
    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            refilled <= 1'b0;
            hit_lat  <= 1'b0;
        end else begin
            state <= next_state;
            if (state == S_IDLE)
                refilled <= 1'b0;
            else if (state == S_ALLOCATE && mem_ready)
                refilled <= 1'b1;
            if (first_lookup)
                hit_lat <= hit;
        end
    end

    // ---------------- next-state + output logic ----------------
    always @(*) begin
        next_state    = state;
        cpu_ready     = 1'b0;
        latch_req     = 1'b0;
        tag_we        = 1'b0;
        valid_we      = 1'b0;
        data_block_we = 1'b0;
        data_word_we  = 1'b0;
        mem_req       = 1'b0;
        mem_we        = 1'b0;

        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    latch_req  = 1'b1;
                    next_state = S_COMPARE;
                end
            end

            S_COMPARE: begin
                if (!req_we) begin                     // LOAD
                    if (hit) begin
                        cpu_ready  = 1'b1;
                        next_state = S_IDLE;
                    end else begin
                        next_state = S_ALLOCATE;
                    end
                end else begin                         // STORE
                    if (hit) data_word_we = 1'b1;      // keep cache coherent with memory
                    next_state = S_WRITE_MEM;
                end
            end

            S_ALLOCATE: begin
                mem_req = 1'b1;
                if (mem_ready) begin
                    data_block_we = 1'b1;
                    tag_we        = 1'b1;
                    valid_we      = 1'b1;
                    next_state    = S_COMPARE;
                end
            end

            S_WRITE_MEM: begin
                mem_req = 1'b1;
                mem_we  = 1'b1;
                if (mem_ready) begin
                    cpu_ready  = 1'b1;
                    next_state = S_IDLE;
                end
            end
        endcase
    end
endmodule
