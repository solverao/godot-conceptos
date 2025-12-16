shader_type spatial;

uniform vec3 color_agua : source_color = vec3(0.0, 0.4, 0.8);
uniform vec3 color_espuma : source_color = vec3(1.0, 1.0, 1.0);

// Texturas de ruido para las olas (usa NoiseTexture2D en el inspector)
uniform sampler2D textura_ruido;
uniform sampler2D textura_normal : hint_normal;

uniform float velocidad = 0.05;
uniform float altura_olas = 0.2;

// Qué tan cerca del terreno empieza la espuma
uniform float borde_espuma = 1.0; 

// Necesario para leer la profundidad (dónde está el terreno debajo del agua)
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

void vertex() {
	// Movimiento simple de olas subiendo y bajando vértices
	float altura = texture(textura_ruido, VERTEX.xz / 20.0 + TIME * velocidad).r;
	VERTEX.y += altura * altura_olas;
}

void fragment() {
	// 1. Movimiento de texturas
	vec2 uv_movimiento = UV + (TIME * velocidad);
	
	// 2. Normal Map (para reflejos y brillo)
	vec3 normal_a = texture(textura_normal, uv_movimiento).rgb;
	vec3 normal_b = texture(textura_normal, uv_movimiento * -0.5 + vec2(0.5)).rgb; // Segunda capa en dir opuesta
	NORMAL_MAP = mix(normal_a, normal_b, 0.5);
	
	// 3. PROXIMITY FADE (Detectar orilla)
	// Leemos la profundidad de la pantalla en este pixel
	float profundidad_escena = texture(depth_texture, SCREEN_UV).r;
	// Convertimos a coordenadas lineales (metros reales)
	vec4 posicion_ndc = vec4(SCREEN_UV * 2.0 - 1.0, profundidad_escena, 1.0);
	vec4 posicion_mundo = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * posicion_ndc;
	posicion_mundo.xyz /= posicion_mundo.w;
	
	// Diferencia entre la superficie del agua (VERTEX) y el terreno debajo (posicion_mundo)
	float profundidad_agua = VERTEX.z - posicion_mundo.z; // En View Space, Z es negativo hacia el fondo
	
	// Nota: En Godot 4, una forma simplificada de obtener esto es usar PROJECTION_MATRIX
	// Pero para simplificar, usaremos el "Linear Depth" manual o visual:
	// La forma más fácil en código shader puro sin complicarse con matrices inversas:
	float profundidad_linear = -VERTEX.z; // Distancia a la cámara del pixel de agua
	// Esto requiere un cálculo más complejo para exactitud perfecta, 
	// pero visualmente podemos usar un truco simple con transparencia:
	
	ALBEDO = color_agua;
	
	// Propiedades básicas PBR
	ROUGHNESS = 0.1; // Muy brillante
	METALLIC = 0.0;
	SPECULAR = 0.5;
	
	// Transparencia básica
	ALPHA = 0.8;
	
	// --- ESPUMA ---
	// Usamos PROXIMITY FADE nativo de Godot si usamos StandardMaterial3D, 
	// pero en shader manual se hace así:
	float profundidad_z = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, profundidad_z);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// Distancia entre el agua y el objeto solido detrás
	float profundidad_diff = linear_depth - (-VERTEX.z);
	
	// Si la diferencia es pequeña (cerca de la orilla), dibujamos espuma
	float factor_espuma = 1.0 - smoothstep(0.0, borde_espuma, profundidad_diff);
	
	// Mezclamos color de agua con espuma
	ALBEDO = mix(color_agua, color_espuma, factor_espuma);
	// Hacemos la espuma totalmente opaca, el agua transparente
	ALPHA = mix(0.8, 1.0, factor_espuma);
}