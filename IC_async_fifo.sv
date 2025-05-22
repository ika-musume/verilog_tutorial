module IC_fifo_async #(parameter DW=16, DEPTH=8) (
    input   wire                    i_RST_n, //reset
    input   wire                    i_WCLK, //write clock
    input   wire                    i_WEN, //write enable
    input   wire signed [DW-1:0]    i_DI, //write data
    output  reg                     o_WFULL, //write buffer full

    input   wire                    i_RCLK, //read clock
    input   wire                    i_REN, //read enable
    output  reg signed  [DW-1:0]    o_DO, //read data
    output  reg                     o_REMPTY
);

parameter   AW = $clog2(DEPTH);

reg         [AW:0]      wa;
reg         [AW:0]      ra;
reg         [AW:0]      wptr, wptr_z, wptr_zz;
reg         [AW:0]      rptr, rptr_z, rptr_zz;
wire        [AW:0]      next_wa, next_wptr;
wire        [AW:0]      next_ra, next_rptr;
reg signed  [DW-1:0]    dpram[AW];

//dual port ram
always_ff @(posedge i_WCLK) if(i_WEN) dpram[wa[AW-1:0]] <= i_DI;
always_ff @(posedge i_RCLK) if(i_REN) o_DO <= dpram[ra[AW-1:0]];

//write side control
always_ff @(posedge i_WCLK or negedge i_RST_n) begin
    if(!i_RST_n) begin
        wa <= 'd0;
        wptr <= 'd0;
    end
    else begin
        if(i_WEN) wa <= next_wa;
        if(i_WEN) wptr <= next_wptr;
    end
end

//write address and encoder
assign next_wa = (wa[AW-1:0] == DEPTH-1) ? {~wa[AW], {AW-1{1'b0}}} : //wraps around
                                           wa + (i_WEN & ~o_WFULL); //next write address
assign next_wptr = next_wa ^ (next_wa >> 1); //gray-coded next write address 

//synchronizer for clock domain crossing
always_ff @(posedge i_WCLK or negedge i_RST_n) begin
    if(!i_RST_n) begin
        rptr_z <= 'd0;
        rptr_zz <= 'd0;
    end
    else begin
        rptr_z <= rptr;
        rptr_zz <= rptr_z;
    end
end

//full flag
always_ff @(posedge i_WCLK or negedge i_RST_n) begin
    if(!i_RST_n) o_WFULL <= 1'b0;
    else begin
        if(next_wptr == {~rptr_zz[AW:AW-1], rptr_zz[AW-2:0]}) o_WFULL <= 1'b1;
        else o_WFULL <= 1'b0;
    end
end


//read side control
always_ff @(posedge i_WCLK or negedge i_RST_n) begin
    if(!i_RST_n) begin
        ra <= 'd0;
        rptr <= 'd0;
    end
    else begin
        if(i_WEN) ra <= next_ra;
        if(i_WEN) rptr <= next_rptr;
    end
end

//read address and encoder
assign next_ra = (ra[AW-1:0] == DEPTH-1) ? {~ra[AW], {AW-1{1'b0}}} : //wraps around
                                           ra + (i_REN & ~o_REMPTY); //next write address
assign next_rptr = next_ra ^ (next_ra >> 1); //gray-coded next write address

//synchronizer for clock domain crossing
always_ff @(posedge i_WCLK or negedge i_RST_n) begin
    if(!i_RST_n) begin
        wptr_z <= 'd0;
        wptr_zz <= 'd0;
    end
    else begin
        wptr_z <= rptr;
        wptr_zz <= rptr_z;
    end
end

//empty flag
always_ff @(posedge i_RCLK or negedge i_RST_n) begin
    if(!i_RST_n) o_REMPTY <= 1'b1;
    else begin
        if(next_rptr == wptr_zz) o_REMPTY <= 1'b1;
        else o_REMPTY <= 1'b0;
    end
end

endmodule