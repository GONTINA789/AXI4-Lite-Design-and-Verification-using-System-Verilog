module axi_slave(in_if.SLAVE inf);
parameter IDLE=3'd0,RADDR_CHANNEL=3'd1,RDATA_CHANNEL=3'd2,WRITE_CHANNEL=3'd3,WRESP_CHANNEL=3'd4;

// Fix: increased memory from 8 to 256 entries to support full 8-bit address range.
// Previously register[7:0] (8 entries) caused out-of-bounds access for addr=20,
// resulting in undefined/zero data being read back.
logic [7:0] register[255:0];

logic add_over,data_over;
logic [2:0] ps,ns;
assign add_over=(inf.M_AWVALID && inf.S_AWREADY)? 1: 0;
assign data_over=(inf.M_WVALID && inf.S_WREADY)? 1: 0;
integer i;

//transition
always_ff @(posedge inf.clk or posedge inf.rst)begin
        if(inf.rst)begin
                ps<=IDLE;
                for(i=0;i<256;i++)begin
                        register[i]=0;
                end
        end
        else begin
                ps<=ns;
                if(ps==WRITE_CHANNEL)
                        register[inf.WADDR]=inf.WDATA;
        end
end

//ns
always_comb begin
       case (ps)
       IDLE : begin
           if (inf.M_AWVALID) begin
               ns = WRITE_CHANNEL;
           end else if (inf.M_ARVALID) begin
               ns = RADDR_CHANNEL;
           end else begin
            ns = IDLE;
           end
       end
        RADDR_CHANNEL: if (inf.M_ARVALID && inf.S_ARREADY) ns = RDATA_CHANNEL;
                       else ns = RADDR_CHANNEL;
        RDATA_CHANNEL: if (inf.S_RVALID  && inf.M_RREADY) ns = IDLE;
                       else ns = RDATA_CHANNEL;
        WRITE_CHANNEL: if (add_over && data_over) ns = WRESP_CHANNEL;
                       else ns = WRITE_CHANNEL;
        WRESP_CHANNEL: if (inf.S_BVALID  && inf.M_BREADY ) ns = IDLE;
                       else ns = WRESP_CHANNEL;
           default : ns = IDLE;
    endcase
end

//output
assign inf.S_ARREADY = (ps == RADDR_CHANNEL) ? 1 : 0;
assign inf.S_RVALID  = (ps == RDATA_CHANNEL) ? 1 : 0;
assign inf.RDATA     = (ps == RDATA_CHANNEL) ? register[inf.RADDR] : 8'd0;
assign inf.S_RRESP   = (ps == RDATA_CHANNEL) ? 2'b00 : 2'b00;  // OKAY response
assign inf.S_AWREADY = (ps == WRITE_CHANNEL) ? 1 : 0;
assign inf.S_WREADY  = (ps == WRITE_CHANNEL) ? 1 : 0;
assign inf.S_BVALID  = (ps == WRESP_CHANNEL) ? 1 : 0;
endmodule
