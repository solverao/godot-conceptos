shader_type spatial;

// --- Texturas de COLOR (Albedo) ---
uniform sampler2D textura_arena : source_color, filter_linear_mipmap;
uniform sampler2D textura_pasto : source_color, filter_linear_mipmap;
uniform sampler2D textura_roca : source_color, filter_linear_mipmap;

// --- Texturas de RELIEVE (Normal Maps) ---
// <--- NUEVAS VARIABLES (Nota el hint_normal)
uniform sampler2D normal_arena : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_pasto : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_roca : hint_normal, filter_linear_mipmap;

// --- Intensidad del relieve ---
uniform float fuerza_relieve : hint_range(0.0, 5.0) = 1.0; 

// --- Configuraciones ---
uniform float altura_transicion = 2.0;
uniform float suavizado_altura = 1.0;
uniform float umbral_pendiente : hint_range(0.0, 1.0) = 0.7;
uniform float suavizado_pendiente : hint_range(0.001, 0.5) = 0.1;
uniform float escala_textura = 20.0;

// Variables Vertex -> Fragment
varying float altura_actual;
varying vec3 normal_terreno;

void vertex() {
	altura_actual = VERTEX.y;
	normal_terreno = NORMAL; 
}

void fragment() {
	vec2 uv_tiling = UV * escala_textura;
	
	// 1. Obtener COLORES
	vec3 color_arena = texture(textura_arena, uv_tiling).rgb;
	vec3 color_pasto = texture(textura_pasto, uv_tiling).rgb;
	vec3 color_roca = texture(textura_roca, uv_tiling).rgb;
	
	// 2. Obtener RELIEVE (Normal Maps) <--- NUEVO
	vec3 n_arena = texture(normal_arena, uv_tiling).rgb;
	vec3 n_pasto = texture(normal_pasto, uv_tiling).rgb;
	vec3 n_roca = texture(normal_roca, uv_tiling).rgb;
	
	// --- CÁLCULO DE MEZCLAS ---
	
	// Mezcla Altura (Arena vs Pasto)
	float mezcla_altura = smoothstep(altura_transicion - suavizado_altura, altura_transicion + suavizado_altura, altura_actual);
	
	// Mezcla Pendiente (Suelo vs Roca)
	float pendiente = dot(normal_terreno, vec3(0.0, 1.0, 0.0));
	float mezcla_roca = smoothstep(umbral_pendiente - suavizado_pendiente, umbral_pendiente + suavizado_pendiente, pendiente);
	
	// --- APLICACIÓN FINAL ---
	
	// 1. Mezclar Colores
	vec3 suelo_base = mix(color_arena, color_pasto, mezcla_altura);
	ALBEDO = mix(color_roca, suelo_base, mezcla_roca);
	
	// 2. Mezclar Normales (Misma lógica que el color) <--- NUEVO
	vec3 n_suelo_base = mix(n_arena, n_pasto, mezcla_altura);
	vec3 n_final = mix(n_roca, n_suelo_base, mezcla_roca);
	
	// Asignar al canal de Normal Map
	NORMAL_MAP = n_final;
	NORMAL_MAP_DEPTH = fuerza_relieve;
}