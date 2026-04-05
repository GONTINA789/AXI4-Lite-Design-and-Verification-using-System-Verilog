module dut(axi_if.DUT axif);
        in_if inf(axif.clk,axif.rst);
        axi_master m1(axif,inf);
        axi_slave s1(inf);
endmodule
