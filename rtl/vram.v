//-------------------------------------------------------------------------------------------------
// Memoria de video de doble puerto: puerto 1 solo lectura (video), puerto 2 lectura/escritura (CPU).
//
// Sustituye en MiSTer al dprf de Kyp: el dprf deja escritura en los dos puertos (aunque el 1 la
// tenga a cero) y lee el dato antiguo al escribir, y Quartus 17 no sabe meter eso en los bloques
// M10K del Cyclone V ("unsupported read-during-write behavior"), asi que lo hace con registros.
// Aqui el puerto 1 no escribe y el 2 devuelve el dato nuevo al escribir.
//-------------------------------------------------------------------------------------------------
module vram
#(
	parameter KB = 16
)
(
	input  wire                      clock,
	input  wire[$clog2(KB*1024)-1:0] a1,
	output reg [                7:0] q1,
	input  wire[$clog2(KB*1024)-1:0] a2,
	input  wire[                7:0] d2,
	output reg [                7:0] q2,
	input  wire                      w2
);

reg[7:0] mem[0:(KB*1024)-1];

always @(posedge clock) q1 <= mem[a1];

always @(posedge clock)
	if(w2) begin mem[a2] <= d2; q2 <= d2; end
	else q2 <= mem[a2];

endmodule
