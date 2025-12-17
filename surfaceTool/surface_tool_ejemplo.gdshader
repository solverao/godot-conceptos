shader_type spatial;

// --- Texturas COLOR ---
uniform sampler2D textura_arena : source_color, filter_linear_mipmap;
uniform sampler2D textura_pasto : source_color, filter_linear_mipmap;
uniform sampler2D textura_roca : source_color, filter_linear_mipmap; // Esta usará Triplanar

// --- Texturas RELIEVE (Normal Maps) ---
uniform sampler2D normal_arena : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_pasto : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_roca : hint_normal, filter_linear_mipmap; // Esta usará Triplanar

uniform float fuerza_relieve : hint_range(0.0, 5.0) = 1.0; 

// --- Configuración ---
uniform float altura_transicion = 2.0;
uniform float suavizado_altura = 1.0;
uniform float umbral_pendiente : hint_range(0.0, 1.0) = 0.7;
uniform float suavizado_pendiente : hint_range(0.001, 0.5) = 0.1;
uniform float escala_textura = 20.0;

// <--- NUEVO: Escala diferente para triplanar (a veces la roca necesita ser más chica/grande)
uniform float escala_triplanar = 0.1; 

// Variables Vertex -> Fragment
varying float altura_actual;
varying vec3 normal_terreno;
varying vec3 pos_mundo; // <--- NUEVO: Necesitamos la posición real en el mundo

// --- FUNCIÓN TRIPLANAR (La magia matemática) ---
vec4 texture_triplanar(sampler2D p_sampler, vec3 p_weights, vec3 p_pos) {
	vec4 samp = vec4(0.0);
	// Proyectar en X (Paredes laterales)
	samp += texture(p_sampler, p_pos.zy) * p_weights.x;
	// Proyectar en Y (Suelo/Techo)
	samp += texture(p_sampler, p_pos.xz) * p_weights.y;
	// Proyectar en Z (Paredes frontales)
	samp += texture(p_sampler, p_pos.xy) * p_weights.z;
	return samp;
}

void vertex() {
	altura_actual = VERTEX.y;
	normal_terreno = NORMAL;
	// Convertimos la posición local a mundial para que la textura se "pegue" al mundo
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv_tiling = UV * escala_textura;
	
	// --- 1. CÁLCULO DE PESOS TRIPLANAR ---
	// Calculamos qué tan fuerte es la normal en cada eje
	vec3 blending = abs(normal_terreno);
	// Normalizamos para que la suma sea siempre 1.0
	blending /= dot(blending, vec3(1.0));
	// Hacemos que la mezcla sea más nítida (opcional, evita que se vea borroso)
	blending = pow(blending, vec3(4.0));
	blending /= dot(blending, vec3(1.0));
	
	// --- 2. OBTENER COLORES ---
	vec3 color_arena = texture(textura_arena, uv_tiling).rgb;
	vec3 color_pasto = texture(textura_pasto, uv_tiling).rgb;
	
	// <--- APLICAMOS TRIPLANAR SOLO A LA ROCA
	// Usamos pos_mundo * escala_triplanar en lugar de UV
	vec3 color_roca = texture_triplanar(textura_roca, blending, pos_mundo * escala_triplanar).rgb;
	
	// --- 3. OBTENER NORMALES ---
	vec3 n_arena = texture(normal_arena, uv_tiling).rgb;
	vec3 n_pasto = texture(normal_pasto, uv_tiling).rgb;
	
	// <--- APLICAMOS TRIPLANAR A LA NORMAL DE ROCA TAMBIÉN
	vec3 n_roca = texture_triplanar(normal_roca, blending, pos_mundo * escala_triplanar).rgb;
	
	// --- 4. MEZCLAS (Igual que antes) ---
	float mezcla_altura = smoothstep(altura_transicion - suavizado_altura, altura_transicion + suavizado_altura, altura_actual);
	
	float pendiente = dot(normal_terreno, vec3(0.0, 1.0, 0.0));
	float mezcla_roca = smoothstep(umbral_pendiente - suavizado_pendiente, umbral_pendiente + suavizado_pendiente, pendiente);
	
	// --- 5. RESULTADO FINAL ---
	vec3 suelo_base = mix(color_arena, color_pasto, mezcla_altura);
	ALBEDO = mix(color_roca, suelo_base, mezcla_roca);
	
	vec3 n_suelo_base = mix(n_arena, n_pasto, mezcla_altura);
	vec3 n_final = mix(n_roca, n_suelo_base, mezcla_roca);
	
	NORMAL_MAP = n_final;
	NORMAL_MAP_DEPTH = fuerza_relieve;
}