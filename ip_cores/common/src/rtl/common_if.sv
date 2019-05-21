/*
  Commonly used interfaces:
    - AXI stream
    - RAM

  Copyright (C) 2019  Benjamin Devlin and Zcash Foundation

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

interface if_axi_stream # (
  parameter DAT_BYTS = 8,
  parameter DAT_BITS = DAT_BYTS*8,
  parameter CTL_BYTS = 1,
  parameter CTL_BITS = CTL_BYTS*8,
  parameter MOD_BITS = DAT_BYTS == 1 ? 1 : $clog2(DAT_BYTS)
)(
  input i_clk
);

  logic rdy;
  logic val;
  logic err;
  logic sop;
  logic eop;
  logic [CTL_BITS-1:0] ctl;
  logic [DAT_BITS-1:0] dat;
  logic [MOD_BITS-1:0] mod;

  modport sink (input val, err, sop, eop, ctl, dat, mod, i_clk, output rdy,
  import task get_keep_from_mod());
  modport source (output val, err, sop, eop, ctl, dat, mod, input rdy, i_clk,
                  import task reset_source(),
                  import task copy_if(dat_, val_, sop_, eop_, err_, mod_, ctl_),
                  import task copy_if_comb(dat_, val_, sop_, eop_, err_, mod_, ctl_),
	  	  import task set_mod_from_keep(keep));

  // Task to reset a source interface signals to all 0
  task reset_source();
    val <= 0;
    err <= 0;
    sop <= 0;
    eop <= 0;
    dat <= 0;
    ctl <= 0;
    mod <= 0;
  endtask

  task copy_if(input logic [DAT_BITS-1:0] dat_=0, input logic val_=0, sop_=0, eop_=0, err_=0, input  logic [MOD_BITS-1:0] mod_=0, input logic [CTL_BITS-1:0] ctl_=0);
    dat <= dat_;
    val <= val_;
    sop <= sop_;
    eop <= eop_;
    mod <= mod_;
    ctl <= ctl_;
    err <= err_;
  endtask

  task copy_if_comb(input logic [DAT_BITS-1:0] dat_=0, input logic val_=0, sop_=0, eop_=0, err_=0, input  logic [MOD_BITS-1:0] mod_=0, input logic [CTL_BITS-1:0] ctl_=0);
    dat = dat_;
    val = val_;
    sop = sop_;
    eop = eop_;
    mod = mod_;
    ctl = ctl_;
    err = err_;
  endtask

  task set_mod_from_keep(input logic [DAT_BYTS-1:0] keep);
    mod = 0;
    for (int i = 0; i < DAT_BYTS; i++)
      if (keep[i])
        mod += 1;	      
  endtask


  function [DAT_BYTS-1:0] get_keep_from_mod();
    get_keep_from_mod = {DAT_BYTS{1'b0}};
    for (int i = 0; i < DAT_BYTS; i++) begin
      if (mod == 0 || i < mod)
        get_keep_from_mod[i] = 1;
    end
    return get_keep_from_mod;
  endfunction

  // Task used in simulation to drive data on a source interface
  task automatic put_stream(input logic [common_pkg::MAX_SIM_BYTS*8-1:0] data,
                            input integer signed len,
                            input logic [CTL_BITS-1:0] ctl_in = 0);
    logic sop_l=0;

    val = 0;
    @(posedge i_clk);

    while (len > 0) begin
      sop = ~sop_l;
      ctl = ctl_in;
      eop = len - DAT_BYTS <= 0;
      val = 1;
      dat = data;
      if (eop) mod = len;
      data = data >> DAT_BITS;
      sop_l = 1;
      len = len - DAT_BYTS;
      @(posedge i_clk); // Go to next clock edge
      while (!rdy) @(posedge i_clk); // If not rdy then wait here
    end
    val = 0;
  endtask

  task print();
    $display("@ %t Interface values .val %h .sop %h .eop %h .err %h .mod 0x%h\n.dat 0x%h", $time, val, sop, eop, err, mod, dat);
  endtask;

  // Task used in simulation to get data from a sink interface
  task automatic get_stream(ref logic [common_pkg::MAX_SIM_BYTS*8-1:0] data, ref integer signed len, input integer unsigned bp = 50);
    logic sop_l = 0;
    logic done = 0;
    logic rdy_l;
    len = 0;
    data = 0;
    rdy_l = rdy;
    rdy = ($urandom % 100) >= bp;
    @(posedge i_clk);

    while (1) begin
      if (val && rdy) begin
        sop_l = sop_l || sop;
        if (!sop_l) begin
          print();
          $fatal(1, "%m %t:ERROR, get_stream() .val without seeing .sop", $time);
        end
        data[len*8 +: DAT_BITS] = dat;
        len = len + (eop ? (mod == 0 ? DAT_BYTS : mod) : DAT_BYTS);
        if (eop) begin
          done = 1;
          break;
        end
      end
      if (~done) begin
        rdy = ($random % 100) >= bp;
        @(posedge i_clk);
      end
    end
    //@(negedge i_clk);

    rdy = rdy_l;
  endtask

endinterface

interface if_axi_mm # (
  parameter D_BITS = 64,
  parameter A_BITS = 8
)(
  input i_clk
);

  logic [A_BITS-1:0] addr;
  logic [D_BITS-1:0] rd_dat;
  logic [D_BITS-1:0] wr_dat;
  logic              wr;
  logic              rd;
  logic              rd_dat_val;
  logic              wait_rq;

  modport sink (input addr, wr_dat, wr, rd, i_clk, output rd_dat, rd_dat_val, wait_rq, import task reset_sink());
  modport source (input rd_dat, rd_dat_val, wait_rq , i_clk, output addr, wr_dat, wr, rd, import task reset_source());

  task reset_source();
    addr <= 0;
    wr_dat <= 0;
    wr <= 0;
    rd <= 0;
  endtask

  task reset_sink();
    rd_dat <= 0;
    rd_dat_val <= 0;
    wait_rq <= 0;
  endtask

  task automatic put_data(input logic [D_BITS-1:0] data, [A_BITS-1:0] addr_in);
    reset_source();
    @(posedge i_clk);
    wr = 1;
    wr_dat = data;
    addr = addr_in;
    @(posedge i_clk); // Go to next clock edge
    while (wait_rq) @(posedge i_clk); // If not rdy then wait here
    reset_source();
  endtask

  task automatic get_data(ref logic [D_BITS-1:0] data, input logic [A_BITS-1:0] addr_in);
    reset_source();
    @(posedge i_clk);
    rd = 1;
    addr = addr_in;
    @(posedge i_clk); // Go to next clock edge
    if (!wait_rq) rd = 0;
    while (!rd_dat_val) begin
      if (!wait_rq) rd = 0;
      @(posedge i_clk);
    end
    data = rd_dat;
    reset_source();
  endtask

endinterface

interface if_ram # (
  parameter RAM_WIDTH = 32,
  parameter RAM_DEPTH = 128
)(
  input i_clk, i_rst
);

  logic [$clog2(RAM_DEPTH)-1:0] a;
  logic en;
  logic we;
  logic re;
  logic [RAM_WIDTH-1:0 ] d, q;

  modport sink (input a, en, re, we, d, i_clk, i_rst, output q);
  modport source (output a, en, re, we, d, input q, i_clk, i_rst, import task reset_source());

  // Task to reset a source interface signals to all 0
  task reset_source();
    a <= 0;
    en <= 0;
    we <= 0;
    re <= 0;
    d <= 0;
  endtask

endinterface
