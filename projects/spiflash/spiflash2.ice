// @sylefeb 2021
// MIT license, see LICENSE_MIT in Silice repo root
// https://github.com/sylefeb/Silice

import('ddr_clock.v')

algorithm spiflash_qspi(
  input  uint8 send,
  input  uint1 trigger,
  input  uint1 send_else_read,
  input  uint1 qspi,
  output uint8 read,
  output uint1 clk,
  inout  uint1 io0,
  inout  uint1 io1,
  inout  uint1 io2,
  inout  uint1 io3,
) {
  uint1 dc(0);
  uint8 sending(0);
  uint1 osc(0);
  uint1 enable(0);

  ddr_clock ddr(clock <: clock, enable <:: enable, ddr_clock :> clk);

  always {

    io0.oenable = send_else_read;
    io1.oenable = send_else_read & qspi;
    io2.oenable = send_else_read & qspi;
    io3.oenable = send_else_read & qspi;

    read      = {read[0,4],io3.i,io2.i,io1.i,io0.i};
    io0.o     = ~osc ? sending[0,1] : sending[4,1];
    io1.o     = ~osc ? sending[1,1] : sending[5,1];
    io2.o     = ~osc ? sending[2,1] : sending[6,1];
    io3.o     = ~osc ? sending[3,1] : sending[7,1];
    
    sending   = (~osc | ~enable) ? send : sending;
    osc       = ~trigger ? 1b0 : ~osc;
    enable    = trigger;
  }
}

algorithm spiflash_rom(
  input   uint1  in_ready,
  input   uint24 addr,
  output  uint8  rdata,
  output  uint1  busy(1),
  // QSPI flash
  output  uint1  sf_csn(1),
  output  uint1  sf_clk,
  inout   uint1  sf_io0,
  inout   uint1  sf_io1,
  inout   uint1  sf_io2,
  inout   uint1  sf_io3,
) <autorun> {

  uint32 sendvec(0); //_ 38h (QPI enable)

  spiflash_qspi spiflash(
    clk     :> sf_clk,
    io0    <:> sf_io0,
    io1    <:> sf_io1,
    io2    <:> sf_io2,
    io3    <:> sf_io3,
  );

  uint10 wait(1023);
  uint4  four(0);
  uint3  stage(0);
  uint3  after(1);
  uint2  init(2b11);
$$if ICARUS then
  uint32 cycle(0);
$$end
  always {

    spiflash.qspi = ~init[1,1]; // qpi activated after first command

    switch (stage)
    {
      case 0: {
$$if ICARUS then
        // this is necessary for icarus as spiflash.qspi is otherwise 1bz
        spiflash.qspi    = reset ? 0 : spiflash.qspi;
        spiflash.trigger = reset ? 0 : spiflash.trigger;
        spiflash.send    = 0;
$$end
        stage = wait == 0 ? after : 0; // NOTE == 0 could be reduced (initial wait is wide)
        wait  = wait - 1;
      }
      case 1: {
        four    = {init[0,1],~init[0,1],2b00};
        sendvec = (init == 2b01 ? {8hEB,addr} : 24h0)
                | (init == 2b00 ? {addr,8h00} : 24h0)
                | (init[1,1]    ? 32b00000000000100010001000000000000 : 24h0);
               //                ^^^^^^^^^^ produces 38h when not in QPI
        spiflash.send_else_read = 1; // sending
        // start sending?
        if (in_ready | init[1,1]) {
$$if ICARUS then
          __display("[%d] spiflash [1] qspi:%d init:%b",cycle,spiflash.qspi,init);
$$end
          busy                  = 1;
          sf_csn                = 0;
          stage                 = 2;
        }
      }
      case 2: {
$$if ICARUS then
        __display("[%d] spiflash [2] qspi:%d init:%b send:%b",cycle,spiflash.qspi,init,sendvec[24,8]);
$$end
        spiflash.trigger        = 1;
        spiflash.send           = sendvec[24,8];
        sendvec                 = sendvec << 8;
        stage                   = 0; // wait
        wait                    = 0; //_ 2 cycles
        after                   = four[0,1] ? 3 : 2;
        four                    = four >> 1;
      }
      case 3: {
        sf_csn                  =  init[1,1]; // not sending anything if in init
        spiflash.trigger        = ~init[1,1];
        // send dummy
        spiflash.send           = 8b00100000; // requests continuous read
        stage                   = 0; // wait
        wait                    = 1; //_ 3 cycles
        after                   = 4;
      }
      case 4: {
        spiflash.send_else_read = 0;
        stage                   = 0; // wait
        wait                    = 0; //_ 2 cycles
        after                   = 5;
      }
      case 5: {
        rdata                   = spiflash.read;
        sf_csn                  = 1;
        spiflash.trigger        = 0;
        busy                    = 0;
        init                    = {1b0,init[1,1]};
        stage                   = 1; // return to start stage
      }
    }
$$if ICARUS then
    cycle = cycle + 1;
$$end
  }
}