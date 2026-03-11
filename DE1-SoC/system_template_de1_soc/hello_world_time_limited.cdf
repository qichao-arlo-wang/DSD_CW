/* Quartus Prime Version 23.1std.0 Build 991 11/28/2023 SC Lite Edition */
JedecChain;
	FileRevision(JESD32A);
	DefaultMfr(6E);

	P ActionCode(Ign)
		Device PartName(5CSEBA5) MfrSpec(OpMask(0));
	P ActionCode(Cfg)
		Device PartName(5CSEMA5F31) Path("C:/Users/arlow/Downloads/DSD_CW/DE1-SoC/system_template_de1_soc/") File("hello_world_time_limited.sof") MfrSpec(OpMask(1));

ChainEnd;

AlteraBegin;
	ChainType(JTAG);
AlteraEnd;
