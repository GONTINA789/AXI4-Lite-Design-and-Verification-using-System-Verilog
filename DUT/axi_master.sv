module axi_master(axi_if.DUT axif,in_if.MASTER inf);
parameter IDLE=3'd0,RADDR_CHANNEL=3'd1,RDATA_CHANNEL=3'd2,WRITE_CHANNEL=3'd3,WRESP_CHANNEL=3'd4;
logic add_over,data_over;
logic [2:0] ps,ns;
assign add_over=(inf.M_AWVALID && inf.S_AWREADY)? 1: 0;
assign data_over=(inf.M_WVALID && inf.S_WREADY)? 1: 0;

//nxt state 
always_comb begin
       case(ps)
        IDLE:begin
                if(axif.start_read==1)
                        ns=RADDR_CHANNEL;
                else if(axif.start_write==1)
                        ns=WRITE_CHANNEL;
                else
                        ns=IDLE;
                
             end
        RADDR_CHANNEL:begin
                        if(inf.S_ARREADY && inf.M_ARVALID)
                                ns=RDATA_CHANNEL;
                        else
                                ns=RADDR_CHANNEL;
                      end
        RDATA_CHANNEL:begin
                        if(inf.S_RVALID && inf.M_RREADY)
                                ns=IDLE;
                        else
                                ns=RDATA_CHANNEL;
                      end
        WRITE_CHANNEL:begin
                        if(add_over && data_over)
                                ns=WRESP_CHANNEL;
                        else
                                ns=WRITE_CHANNEL;
                      end
        WRESP_CHANNEL:begin
                        if(inf.S_BVALID && inf.M_BREADY)
                                ns=IDLE;
                        else
                                ns=WRESP_CHANNEL;
                      end
                default:ns=IDLE;
       endcase

end

//state transition
always_ff @(posedge axif.clk or posedge axif.rst)begin
//$display("M_arvalid = %0d ",inf.M_ARVALID);
        if(axif.rst)begin
                ps<=IDLE;
        end
        else begin
                ps<=ns;       
        end
end

//output logic
assign inf.M_ARVALID=(ps==RADDR_CHANNEL)?1:0;
assign inf.RADDR=(ps==RADDR_CHANNEL)?axif.addr:8'd0;
assign inf.M_RREADY=(ps==RADDR_CHANNEL || ps==RDATA_CHANNEL)? 1: 0;
assign inf.M_AWVALID=(ps==WRITE_CHANNEL)?1:0;
assign inf.M_WVALID=(ps==WRITE_CHANNEL)?1:0;
assign inf.M_BREADY=(ps==WRITE_CHANNEL||ps==WRESP_CHANNEL)?1:0;
assign inf.WADDR=(ps==WRITE_CHANNEL)?axif.addr:8'd0;
assign inf.WDATA=(ps==WRITE_CHANNEL)?axif.wdata:8'd0;
assign axif.rdata=inf.RDATA;
endmodule
