module IC_fifo_sync #(parameter DW=16, DEPTH=8) (
    input   wire                            i_RST_n,
    input   wire                            i_CLK,
    input   wire                            i_WEN, //write enable
    input   wire signed [DW-1:0]            i_DI,  //write data

    input   wire                            i_REN, // read enable
    output  reg signed  [DW-1:0]            o_DO,  // read data

    output  reg         [$clog2(DEPTH):0]   o_CNTR // counter
);

parameter   AW = $clog2(DEPTH);

reg         [AW-1:0]    wa;
reg         [AW-1:0]    ra;
reg signed  [DW-1:0]    dpram[DEPTH];

//dual port RAM(register file made with DFFs)
always_ff @(posedge i_CLK) begin
    if(i_WEN) dpram[wa] <= i_DI;
    if(i_REN) o_DO <= dpram[ra];
end

//write address
always_ff @(posedge i_CLK or negedge i_RST_n) begin
    if(!i_RST_n) wa <= 'd0;
    else begin
        if(i_WEN) wa <= wa + 'd1;
    end
end

//read address
always_ff @(posedge i_CLK or negedge i_RST_n) begin
    if(!i_RST_n) ra <= 'd0;
    else begin
        if(i_REN) ra <= ra + 'd1;
    end
end

//data stack counter
always_ff @(posedge i_CLK or negedge i_RST_n) begin
    if(!i_RST_n) o_CNTR <= 'd0;
    else begin
        case({i_WEN,i_REN})
        2'b00: o_CNTR <= o_CNTR;
        2'b01: o_CNTR <= o_CNTR - 'd1;
        2'b10: o_CNTR <= o_CNTR + 'd1;
        2'b11: o_CNTR <= o_CNTR;
        endcase
    end
end

endmodule