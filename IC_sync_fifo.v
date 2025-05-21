module IC_sync_fifo #(parameter AW=8, DW=16) (
    input   wire                    i_RST,
    input   wire                    i_CLK,
    input   wire                    i_WEN, //write enable
    input   wire signed [DW-1:0]    i_DI,  //write data

    input   wire                    i_REN, // read enable
    output  reg signed  [DW-1:0]    o_DO,  // read data

    output  reg         [AW:0]      o_CNTR // counter
);

reg         [AW-1:0]    wa;
reg         [AW-1:0]    ra;
reg signed  [DW-1:0]    dpram[0:2**AW-1];

//dual port RAM(register file made with DFFs)
always @(posedge i_CLK) begin
    if(i_WEN) dpram[wa] <= i_DI;
    if(i_REN) o_DO <= dpram[ra];
end

//write address
always @(posedge i_CLK or posedge i_RST) begin
    if(i_RST) wa <= {AW{1'b0}};
    else begin
        if(i_WEN) wa <= wa + 1'b1;
    end
end

//read address
always @(posedge i_CLK or posedge i_RST) begin
    if(i_RST) ra <= {AW{1'b0}};
    else begin
        if(i_REN) ra <= ra + 1'b1;
    end
end

//data stack counter
always @(posedge i_CLK or posedge i_RST) begin
    if(i_RST) o_CNTR <= {(AW+1){1'b0}};
    else begin
        case({i_WEN,i_REN})
        2'b00: o_CNTR <= o_CNTR;
        2'b01: o_CNTR <= o_CNTR - 1'b1;
        2'b10: o_CNTR <= o_CNTR + 1'b1;
        2'b11: o_CNTR <= o_CNTR;
        endcase
    end
end

endmodule