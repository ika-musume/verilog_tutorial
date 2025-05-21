module IC_async_fifo #(parameter AW=8, DW=16) (
    input   wire                    i_RST, //reset
    input   wire                    i_WCLK, //write clock
    input   wire                    i_WEN, //write enable
    input   wire signed [DW-1:0]    i_DI, //write data
    output  reg                     o_WFULL, //write buffer full

    input   wire                    i_RCLK, //read clock
    input   wire                    i_REN, //read enable
    output  reg signed  [DW-1:0]    o_DO, //read data
    output  reg                     o_REMPTY
);

reg         [AW:0]      wa;
reg         [AW:0]      ra;
reg         [AW:0]      wptr, wptr_z, wptr_zz;
reg         [AW:0]      rptr, rptr_z, rptr_zz;
wire        [AW:0]      next_wa, next_wptr;
wire        [AW:0]      next_ra, next_rptr;
reg signed  [DW-1:0]    dpram[0:2**AW-1];

//dual port ram
always @(posedge i_WCLK) if(i_WEN) dpram[wa[AW-1:0]] <= i_DI;
always @(posedge i_RCLK) if(i_REN) o_DO <= dpram[ra[AW-1:0]];

//write side control
always @(posedge i_WCLK or posedge i_RST) begin
    if(i_RST) {wa, wptr} <= {{(AW+1){1'b0}}, {(AW+1){1'b0}}};
    else begin
        if(i_WEN) {wa, wptr} <= {next_wa, next_wptr};
    end
end

//write address and encoder
assign next_wa = wa + (i_WEN & ~o_WFULL); //next write address
assign next_wptr = next_wa ^ (next_wa >> 1'b1); //gray-coded next write address 

//synchronizer for clock domain crossing
always @(posedge i_WCLK or posedge i_RST) begin
    if(i_RST) {rptr_zz, rptr_z} <= {{(AW+1){1'b0}}, {(AW+1){1'b0}}};
    else begin
        {rptr_zz, rptr_z} <= {rptr_z, rptr};
    end
end

//full flag
always @(posedge i_WCLK or posedge i_RST) begin
    if(i_RST) o_WFULL <= 1'b0;
    else begin
        if(next_wptr == {~rptr_zz[AW:AW-1], rptr_zz[AW-2:0]}) o_WFULL <= 1'b1;
        else o_WFULL <= 1'b0;
    end
end


//read side control
always @(posedge i_RCLK or posedge i_RST) begin
    if(i_RST) {ra, rptr} <= {{(AW+1){1'b0}}, {(AW+1){1'b0}}};
    else begin
        if(i_REN) {ra, rptr} <= {next_ra, next_rptr};
    end
end

//read address and encoder
assign next_ra = ra + (i_REN & ~o_REMPTY); //next write address
assign next_rptr = next_ra ^ (next_ra >> 1); //gray-coded next write address

//synchronizer for clock domain crossing
always @(posedge i_RCLK or posedge i_RST) begin
    if(i_RST) {wptr_zz, wptr_z} <= {{(AW+1){1'b0}}, {(AW+1){1'b0}}};
    else begin
        {wptr_zz,wptr_z} <= {wptr_z,wptr};
    end
end

//empty flag
always @(posedge i_RCLK or posedge i_RST) begin
    if(i_RST) o_REMPTY <= 1'b1;
    else begin
        if(next_rptr == wptr_zz) o_REMPTY <= 1'b1;
        else o_REMPTY <= 1'b0;
    end
end

endmodule