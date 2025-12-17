extends MeshInstance3D

@export_group("Agua")
@export var generar_agua := true
@export var nivel_agua := 2.0  # Debería ser similar a tu altura_transicion del terreno
@export var material_agua : Material

@export_group("Vegetación")
@export var mesh_arbol: Mesh
@export var cantidad_arboles: int = 900
@export var escala_arbol_min: float = 0.8
@export var escala_arbol_max: float = 1.5
# Altura mínima para que crezca un árbol (evitar arena/agua)
@export var altura_minima_vegetacion: float = 2.5
# Qué tan empinado puede ser el terreno (0.0 pared, 1.0 plano). 
# 0.7 es aprox 45 grados.
@export var umbral_pendiente_arboles: float = 0.7


@export var mapa_altura: Texture2D
@export_range(0.1, 100.0, 0.1) var altura_maxima := 10.0
@export_range(0.1, 10.0, 0.1) var escala_xz := 1.0
@export var centrar_terreno := true

func _ready():
	if mapa_altura == null:
		push_error("No hay heightmap asignado")
		return
	
	var ruta := _ruta_cache()
	if ResourceLoader.exists(ruta):
		mesh = load(ruta)
		_post_generar()
		return
	
	generar_terreno()
	generar_vegetacion()

func _ruta_cache() -> String:
	var hash := str(mapa_altura.resource_path, altura_maxima, escala_xz).hash()
	return "res://meshes/terrain_%s.res" % hash

func generar_terreno():
	var img := mapa_altura.get_image()
	var ancho := img.get_width()
	var alto := img.get_height()
	
	# Leer TODOS los píxeles de una vez (mucho más rápido)
	var datos := img.get_data()
	var formato := img.get_format()
	var bytes_por_pixel := _bytes_por_formato(formato)
	
	# Pre-calcular offset de centrado
	var offset_x := (ancho * escala_xz) / 2.0 if centrar_terreno else 0.0
	var offset_z := (alto * escala_xz) / 2.0 if centrar_terreno else 0.0
	
	# Pre-asignar arrays (evita realocaciones)
	var num_vertices := ancho * alto
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	vertices.resize(num_vertices)
	uvs.resize(num_vertices)
	
	# Generar vértices
	for z in alto:
		var fila := z * ancho
		for x in ancho:
			var idx := fila + x
			var pixel_idx := idx * bytes_por_pixel
			
			# Leer canal rojo (primer byte) directamente del buffer
			var altura := (datos[pixel_idx] / 255.0) * altura_maxima
			
			vertices[idx] = Vector3(
				x * escala_xz - offset_x,
				altura,
				z * escala_xz - offset_z
			)
			uvs[idx] = Vector2(float(x) / ancho, float(z) / alto)
	
	# Pre-calcular tamaño de índices
	var num_quads := (ancho - 1) * (alto - 1)
	indices.resize(num_quads * 6)
	
	var i := 0
	for z in alto - 1:
		var fila := z * ancho
		for x in ancho - 1:
			var actual := fila + x
			var derecha := actual + 1
			var abajo := actual + ancho
			var abajo_derecha := abajo + 1
			
			# Triángulo 1 (CCW para Godot)
			indices[i] = actual
			indices[i + 1] = derecha
			indices[i + 2] = abajo
			
			# Triángulo 2
			indices[i + 3] = derecha
			indices[i + 4] = abajo_derecha
			indices[i + 5] = abajo
			
			i += 6
	
	# Construir mesh con SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for idx in num_vertices:
		st.set_uv(uvs[idx])
		st.add_vertex(vertices[idx])
	
	for idx in indices:
		st.add_index(idx)
	
	st.generate_normals()
	st.generate_tangents()  # Importante para normal maps
	mesh = st.commit()
	
	ResourceSaver.save(mesh, _ruta_cache())
	_post_generar()
	
	if generar_agua:
		crear_plano_agua(ancho, alto)

func _post_generar():
	create_trimesh_collision()
	
	if get_parent() is NavigationRegion3D:
		get_parent().bake_navigation_mesh.call_deferred(true)

func _bytes_por_formato(formato: int) -> int:
	match formato:
		Image.FORMAT_L8, Image.FORMAT_R8:
			return 1
		Image.FORMAT_RGB8:
			return 3
		Image.FORMAT_RGBA8:
			return 4
		_:
			push_warning("Formato no optimizado, usando 4 bytes")
			return 4


func crear_plano_agua(ancho_mapa: int, alto_mapa: int):
	# Verificar si ya existe agua previa y borrarla para evitar duplicados
	if has_node("Agua"):
		get_node("Agua").queue_free()

	var mesh_agua = PlaneMesh.new()
	
	# Ajustamos el tamaño. El PlaneMesh por defecto mide 2x2, así que dividimos.
	# Pero es más fácil asignar el size directamente:
	mesh_agua.size = Vector2(ancho_mapa * escala_xz, alto_mapa * escala_xz)
	
	var agua_node = MeshInstance3D.new()
	agua_node.name = "Agua"
	agua_node.mesh = mesh_agua
	agua_node.material_override = material_agua
	
	# Posición Y: La altura del nivel del mar
	agua_node.position.y = nivel_agua
	
	# Centrado: Si tu terreno está centrado, el agua también debe estarlo (0, Y, 0).
	# Si tu terreno NO está centrado, tienes que mover el agua al centro del mapa.
	if not centrar_terreno:
		agua_node.position.x = (ancho_mapa * escala_xz) / 2.0
		agua_node.position.z = (alto_mapa * escala_xz) / 2.0
		
	add_child(agua_node)


func generar_vegetacion():
	if mesh_arbol == null:
		print("No hay mesh de árbol asignado")
		return

	# Limpiar vegetación anterior si existe
	if has_node("Vegetacion"):
		get_node("Vegetacion").queue_free()

	# Crear el nodo MultiMeshInstance3D
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "Vegetacion"
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_arbol
	# Reservamos espacio para los árboles (esto no los dibuja aún, solo asigna memoria)
	mm.instance_count = cantidad_arboles 
	mmi.multimesh = mm
	add_child(mmi)

	# Datos necesarios para calcular posiciones
	var img := mapa_altura.get_image()
	var ancho := img.get_width()
	var alto := img.get_height()
	var offset_x := (ancho * escala_xz) / 2.0 if centrar_terreno else 0.0
	var offset_z := (alto * escala_xz) / 2.0 if centrar_terreno else 0.0
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var arboles_colocados = 0
	
	# Intentamos colocar árboles hasta llenar el cupo
	# Usamos un bucle while para reintentar si caen en agua o roca
	var intentos = 0
	var max_intentos = cantidad_arboles * 5 # Evitar bucle infinito
	
	while arboles_colocados < cantidad_arboles and intentos < max_intentos:
		intentos += 1
		
		# 1. Posición aleatoria en la imagen (evitando los bordes exactos)
		var px = rng.randi_range(1, ancho - 2)
		var pz = rng.randi_range(1, alto - 2)
		
		# 2. Obtener altura (0 a 1)
		var h_pixel = img.get_pixel(px, pz).r
		var altura_real = h_pixel * altura_maxima
		
		# FILTRO 1: Altura (No agua, no arena)
		if altura_real < altura_minima_vegetacion:
			continue # Saltar al siguiente intento
			
		# 3. Calcular pendiente (Normal)
		# Comparamos la altura del vecino derecho y el vecino de abajo
		var h_derecha = img.get_pixel(px + 1, pz).r * altura_maxima
		var h_abajo = img.get_pixel(px, pz + 1).r * altura_maxima
		
		var vec_u = Vector3(escala_xz, h_derecha - altura_real, 0)
		var vec_v = Vector3(0, h_abajo - altura_real, escala_xz)
		var normal = vec_v.cross(vec_u).normalized()
		
		# FILTRO 2: Pendiente (No paredes de roca)
		# Producto punto con Vector Arriba (0,1,0). 1 es plano, 0 es vertical.
		if normal.dot(Vector3.UP) < umbral_pendiente_arboles:
			continue
		
		# --- ÉXITO: Colocar Árbol ---
		var pos_x = px * escala_xz - offset_x
		var pos_z = pz * escala_xz - offset_z
		
		var transform = Transform3D()
		# Posición
		transform.origin = Vector3(pos_x, altura_real, pos_z)
		
		# Rotación aleatoria en Y (para que no se vean todos iguales)
		transform = transform.rotated_local(Vector3.UP, rng.randf() * TAU)
		
		# Escala aleatoria
		var escala_random = rng.randf_range(escala_arbol_min, escala_arbol_max)
		transform = transform.scaled_local(Vector3.ONE * escala_random)
		
		# Alinear con el terreno (Opcional, si quieres que crezcan torcidos en laderas)
		# Si prefieres que crezcan siempre rectos hacia arriba, borra las siguientes 3 líneas:
		# var up = Vector3.UP
		# var axis = up.cross(normal).normalized()
		# var angle = acos(up.dot(normal))
		# if axis.length_squared() > 0.001: transform = transform.rotated(axis, angle * 0.5) 
		
		# Guardar en el MultiMesh
		mm.set_instance_transform(arboles_colocados, transform)
		arboles_colocados += 1
	
	# Si no logramos poner todos (por falta de espacio válido), recortamos el array para no dibujar fantasmas
	mm.visible_instance_count = arboles_colocados
	print("Se colocaron ", arboles_colocados, " árboles.")
