/* 
    PIPELINED RADIX-4 BOOTH MULTIPLIER WITH CONFIGURABLE INPUTS
    (C)2025 Raki(Sehyeon Kim)

    DWX = X input data width  
    DWY = Y input data width  
    PIPE = n-bit configuration for pipelining, where n = (DWX / 2) + (DWX % 2)  
    PIPE[n-1...0] = 1 to insert flops, 0 to leave it combinational  
    e.g., 4'b1111 inserts flops at every stage; 4'b1010 inserts flops every two stages

    Note:
    The "_ref" version extends the sign extension of the intermediate stage to DWX+DWY.
    This makes it easier for simulation tools to see the values in the registers.
    It turns out that Design Compiler assigns valid circuits to the "dummy" MSBs for
    sign extension. Actually, in the early stages, the MSBs are just duplicates of
    the sign bit in the narrower adder, and there's no reason to use them. Stupidly
    DC does. I deliberately truncated the width of the adder; this improves PPA.
*/

module IC_bmul_rd4 #(parameter DWX = 8, parameter DWY = 8, parameter PIPE = 0) (
    input   wire                        i_CLK,
    input   wire signed [DWX-1:0]       i_X,
    input   wire signed [DWY-1:0]       i_Y,
    output  wire signed [DWX+DWY-1:0]   o_Z
);

//calculate total stages
localparam PP_NUM = (DWX/2) + (DWX%2); //4 if 8, 5 if 9
localparam FA_DW  = DWY+4; //booth decoder adds 1-bit for doubling + 2-bit shift at every stage + carry out 1-bit

//define radix-4 decoder
function automatic signed [DWY:0] r4dec (input [DWY-1:0] val, input [2:0] ctrl); begin
case(ctrl)
    3'd0 : r4dec = 'd0;
    3'd1 : r4dec = {val[DWY-1], val};
    3'd2 : r4dec = {val[DWY-1], val};
    3'd3 : r4dec = {val, 1'b0};
    3'd4 : r4dec = {~val, 1'b1};
    3'd5 : r4dec = {~val[DWY-1], ~val};
    3'd6 : r4dec = {~val[DWY-1], ~val};
    3'd7 : r4dec = 'd0;
endcase
end endfunction

//make configurable shift register for arbitrary pipelining
reg         [DWX+1:0]       x_ex_sr[PP_NUM-2:-1];
reg signed  [DWY-1:0]       y_sr[PP_NUM-2:-1];
always_comb begin
    x_ex_sr[-1] = (DWX%2) ? {i_X, 2'b00} : {1'b0, i_X, 1'b0}; //extend X input
    y_sr[-1] = i_Y;
end
genvar sr_iter;
generate
for(sr_iter=0; sr_iter<PP_NUM-1; sr_iter=sr_iter+1) begin
    if(PIPE[sr_iter] == 1'b0) begin //no pipeline
        always_comb x_ex_sr[sr_iter] = x_ex_sr[sr_iter-1];
        always_comb y_sr[sr_iter] = y_sr[sr_iter-1];
    end
    else begin //insert pipeline
        always_ff @(posedge i_CLK) x_ex_sr[sr_iter] <= x_ex_sr[sr_iter-1];
        always_ff @(posedge i_CLK) y_sr[sr_iter] <= y_sr[sr_iter-1];
    end
end
endgenerate


//pipelined accumulator array of partial products
reg signed  [DWX+DWY:0]     pp_sr[PP_NUM];

genvar pp_iter;
generate for(pp_iter=0; pp_iter<PP_NUM; pp_iter=pp_iter+1) begin

//Declare parameters for this step
parameter   fa_s_bot = pp_iter*2; //full adder's bottom bit position in pp_sr
parameter   fa_s_top = (fa_s_bot-1+FA_DW) > DWX+DWY ? DWX+DWY : fa_s_bot-1+FA_DW; //full adder's top bit position in pp_sr, should be saturated
parameter   fa_s_dw  = fa_s_top-fa_s_bot+1; //full adder's data width
parameter   fa_a_bot = pp_iter*2; //addend-A's bottom bit; from the previous pp_sr stage
parameter   fa_a_top = fa_s_top-3; //addend-A's top bit; from the previous pp_sr stage
parameter   fa_a_sx  = 3; //addend-A's sign extension bits
parameter   fa_a_dw  = fa_a_top-fa_a_bot+1+fa_a_sx; //this must match fa_s_dw for proper sign handling
parameter   fa_b_sx  = fa_a_dw - DWY; //addend-B's sign extension bits
parameter   fa_b_dw  = DWY+1+fa_b_sx; //addend-B's data width, this must match fa_s_dw

wire        [2:0]                   r4d_ctrl = x_ex_sr[pp_iter-1][pp_iter*2+:3];
wire signed [DWY:0]                 r4d_val  = r4dec(y_sr[pp_iter-1], r4d_ctrl);
wire                                fa_ci = x_ex_sr[pp_iter-1][2+(pp_iter*2)] == 1'b1 && x_ex_sr[pp_iter-1][2+(pp_iter*2)-:3] != 3'b111;
wire signed [fa_a_dw-1:0]           fa_a  = {{fa_a_sx{pp_sr[pp_iter-1][fa_a_top]}}, pp_sr[pp_iter-1][fa_a_top:fa_a_bot]};
wire signed [fa_b_dw-1:0]           fa_b  = {{fa_b_sx{r4d_val[DWY]}}, r4d_val};
wire signed [fa_s_dw-1:0]           fa_s  = pp_iter == 0 ? fa_b + fa_ci : fa_a + fa_b + fa_ci; //can be replaced with any CLA primitives

//make the first stage, carry propagation adder
if(pp_iter == 0) begin
    if(PIPE[pp_iter] == 0) always_comb
        pp_sr[pp_iter][fa_s_top:fa_s_bot] = fa_s;
    else always_ff @(posedge i_CLK)
        pp_sr[pp_iter][fa_s_top:fa_s_bot] <= fa_s;
end

//remaining stages
else begin
    if(PIPE[pp_iter] == 0) always_comb begin
        pp_sr[pp_iter][0+:pp_iter*2] = pp_sr[pp_iter-1][0+:pp_iter*2]; //shift LSBs
        pp_sr[pp_iter][fa_s_top:fa_s_bot] = fa_s;
    end
    else always_ff @(posedge i_CLK) begin
        pp_sr[pp_iter][0+:pp_iter*2] <= pp_sr[pp_iter-1][0+:pp_iter*2]; //shift LSBs
        pp_sr[pp_iter][fa_s_top:fa_s_bot] <= fa_s;
    end
end
end endgenerate

assign  o_Z = (DWX%2) ? pp_sr[PP_NUM-1][DWX+DWY:1] : pp_sr[PP_NUM-1][DWX+DWY-1:0];

endmodule


/*
module IC_bmul_rd4_ref #(parameter DWX = 8, parameter DWY = 8, parameter PIPE = 0) (
    input   wire                        i_CLK,
    input   wire signed [DWX-1:0]       i_X,
    input   wire signed [DWY-1:0]       i_Y,
    output  wire signed [DWX+DWY-1:0]   o_Z
);

//calculate total stages
localparam PP_NUM = (DWX/2) + (DWX%2); //4 if 8, 5 if 9

//define radix-4 decoder
function automatic signed [DWY:0] r4dec (input [DWY-1:0] val, input [2:0] ctrl); begin
case(ctrl)
    3'd0 : r4dec = 'd0;
    3'd1 : r4dec = {val[DWY-1], val};
    3'd2 : r4dec = {val[DWY-1], val};
    3'd3 : r4dec = {val, 1'b0};
    3'd4 : r4dec = {~val, 1'b1};
    3'd5 : r4dec = {~val[DWY-1], ~val};
    3'd6 : r4dec = {~val[DWY-1], ~val};
    3'd7 : r4dec = 'd0;
endcase
end endfunction

//make configurable shift register for arbitrary pipelining
reg         [DWX+1:0]       x_ex_sr[PP_NUM-2:-1];
reg signed  [DWY-1:0]       y_sr[PP_NUM-2:-1];
always_comb begin
    x_ex_sr[-1] = (DWX%2) ? {i_X, 2'b00} : {1'b0, i_X, 1'b0}; //extend X input
    y_sr[-1] = i_Y;
end
genvar sr_iter;
generate
for(sr_iter=0; sr_iter<PP_NUM-1; sr_iter=sr_iter+1) begin
    if(PIPE[sr_iter] == 1'b0) begin //no pipeline
        always_comb x_ex_sr[sr_iter] = x_ex_sr[sr_iter-1];
        always_comb y_sr[sr_iter] = y_sr[sr_iter-1];
    end
    else begin //insert pipeline
        always_ff @(posedge i_CLK) x_ex_sr[sr_iter] <= x_ex_sr[sr_iter-1];
        always_ff @(posedge i_CLK) y_sr[sr_iter] <= y_sr[sr_iter-1];
    end
end
endgenerate


//pipelined accumulator array of partial products
reg signed  [DWX+DWY:0]     pp_sr[PP_NUM];

genvar pp_iter;
generate for(pp_iter=0; pp_iter<PP_NUM; pp_iter=pp_iter+1) begin

wire        [2:0]                   r4d_ctrl = x_ex_sr[pp_iter-1][pp_iter*2+:3];
wire                                fa_ci = x_ex_sr[pp_iter-1][2+(pp_iter*2)] == 1'b1 && x_ex_sr[pp_iter-1][2+(pp_iter*2)-:3] != 3'b111;
wire signed [DWX+DWY-pp_iter*2:0]   fa_a  = pp_sr[pp_iter-1][DWX+DWY:pp_iter*2];
wire signed [DWY:0]                 fa_b  = r4dec(y_sr[pp_iter-1], r4d_ctrl);

//make the first stage, carry propagation adder
if(pp_iter == 0) begin
    if(PIPE[pp_iter] == 0) always_comb
        pp_sr[pp_iter]  = {{(DWX+1-pp_iter*2){fa_b[DWY]}}, fa_b} + fa_ci;
    else always_ff @(posedge i_CLK)
        pp_sr[pp_iter] <= {{(DWX+1-pp_iter*2){fa_b[DWY]}}, fa_b} + fa_ci;
end

//remaining stages
else begin
    if(PIPE[pp_iter] == 0) always_comb begin
        pp_sr[pp_iter][0+:pp_iter*2] = pp_sr[pp_iter-1][0+:pp_iter*2]; //shift LSBs
        pp_sr[pp_iter][DWX+DWY:pp_iter*2] = fa_a + {{(DWX+1-pp_iter*2){fa_b[DWY]}}, fa_b} + fa_ci;
    end
    else always_ff @(posedge i_CLK) begin
        pp_sr[pp_iter][0+:pp_iter*2] <= pp_sr[pp_iter-1][0+:pp_iter*2]; //shift LSBs
        pp_sr[pp_iter][DWX+DWY:pp_iter*2] <= fa_a + {{(DWX+1-pp_iter*2){fa_b[DWY]}}, fa_b} + fa_ci;
    end
end
end endgenerate

assign  o_Z = (DWX%2) ? pp_sr[PP_NUM-1][DWX+DWY:1] : pp_sr[PP_NUM-1][DWX+DWY-1:0];

endmodule
*/
