interface axi_if(input bit clk);
logic rst,start_read,start_write;
logic [7:0]addr,rdata,wdata;
// wdata is driven by TB into the DUT, so it must be an input
modport DUT(input clk,rst,start_read,start_write,addr,wdata,output rdata);
endinterface
