extends MeshInstance3D

@export_group("Configuración General")
@export var mapa_altura: Texture2D
@export_range(0.1, 100.0, 0.1) var altura_maxima := 10.0
@export_range(0.1, 10.0, 0.1) var escala_xz := 1.0
@export var centrar_terreno := true

@export_group("Agua")
@export var generar_agua := true
@export var nivel_agua := 2.0 
@export var material_agua : Material

@export_group("Vegetación")
@export var mesh_arbol: Mesh
@export var cantidad_arboles: int = 900
@export var escala_arbol_min: float = 0.8
@export var escala_arbol_max: float = 1.5
@export var altura_minima_vegetacion: float = 2.5
@export var umbral_pendiente_arboles: float = 0.7

func _ready():
	if mapa_altura == null:
		push_error("Error: No hay heightmap asignado en el terreno.")
		return
	
	# 1. Obtenemos dimensiones una sola vez para usarlas en todo
	var img := mapa_altura.get_image()
	var ancho := img.get_width()
	var alto := img.get_height()
	
	# 2. Intentamos cargar caché o generamos de cero
	var ruta := _ruta_cache()
	
	if ResourceLoader.exists(ruta):
		print("Cargando terreno desde caché...")
		mesh = load(ruta)
	else:
		print("Generando terreno nuevo...")
		generar_terreno(img, ancho, alto)
	
	# 3. Pasos posteriores (se ejecutan SIEMPRE)
	_post_generar()
	
	if generar_agua:
		crear_plano_agua(ancho, alto)
		
	generar_vegetacion(img, ancho, alto)

func _ruta_cache() -> String:
	# Incluimos escala y altura en el hash para que si cambias valores, se regenere
	var hash_val := str(mapa_altura.resource_path, altura_maxima, escala_xz).hash()
	return "res://meshes/terrain_%s.res" % hash_val

func generar_terreno(img: Image, ancho: int, alto: int):
	# Leer TODOS los píxeles de una vez
	var datos := img.get_data()
	var formato := img.get_format()
	var bytes_por_pixel := _bytes_por_formato(formato)
	
	var offset_x := (ancho * escala_xz) / 2.0 if centrar_terreno else 0.0
	var offset_z := (alto * escala_xz) / 2.0 if centrar_terreno else 0.0
	
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
			
			var altura := (datos[pixel_idx] / 255.0) * altura_maxima
			
			vertices[idx] = Vector3(
				x * escala_xz - offset_x,
				altura,
				z * escala_xz - offset_z
			)
			uvs[idx] = Vector2(float(x) / ancho, float(z) / alto)
	
	# Generar índices (Quads)
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
			
			# Triángulo 1
			indices[i] = actual
			indices[i + 1] = derecha 
			indices[i + 2] = abajo
			
			# Triángulo 2
			indices[i + 3] = derecha
			indices[i + 4] = abajo_derecha
			indices[i + 5] = abajo
			
			i += 6
	
	# Construir mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for idx in num_vertices:
		st.set_uv(uvs[idx])
		st.add_vertex(vertices[idx])
	
	for idx in indices:
		st.add_index(idx)
	
	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()
	
	# Guardar en caché
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("meshes"):
		dir.make_dir("meshes") # Crea la carpeta si no existe
		
	ResourceSaver.save(mesh, _ruta_cache())

func _post_generar():
	create_trimesh_collision()
	# Si usas navegación, esto actualiza el mapa
	if get_parent() is NavigationRegion3D:
		get_parent().bake_navigation_mesh.call_deferred(true)

func crear_plano_agua(ancho_mapa: int, alto_mapa: int):
	if has_node("Agua"):
		get_node("Agua").queue_free()

	var mesh_agua = PlaneMesh.new()
	mesh_agua.size = Vector2(ancho_mapa * escala_xz, alto_mapa * escala_xz)
	
	var agua_node = MeshInstance3D.new()
	agua_node.name = "Agua"
	agua_node.mesh = mesh_agua
	
	if material_agua:
		agua_node.material_override = material_agua
	else:
		push_warning("Advertencia: No se ha asignado un Material de Agua.")
	
	agua_node.position.y = nivel_agua
	
	if not centrar_terreno:
		agua_node.position.x = (ancho_mapa * escala_xz) / 2.0
		agua_node.position.z = (alto_mapa * escala_xz) / 2.0
		
	add_child(agua_node)

func generar_vegetacion(img: Image, ancho: int, alto: int):
	if mesh_arbol == null: return

	if has_node("Vegetacion"): get_node("Vegetacion").queue_free()
	if has_node("ColisionesArboles"): get_node("ColisionesArboles").queue_free()

	var mmi = MultiMeshInstance3D.new()
	mmi.name = "Vegetacion"
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_arbol
	mm.instance_count = cantidad_arboles 
	mmi.multimesh = mm
	add_child(mmi)
	
	var col_container = Node3D.new()
	col_container.name = "ColisionesArboles"
	add_child(col_container)

	var offset_x := (ancho * escala_xz) / 2.0 if centrar_terreno else 0.0
	var offset_z := (alto * escala_xz) / 2.0 if centrar_terreno else 0.0
	
	var rng = RandomNumberGenerator.new()
	rng.randomize() # Importante para que no salgan siempre en el mismo lugar
	
	var arboles_colocados = 0
	var intentos = 0
	var max_intentos = cantidad_arboles * 10 # Aumenté un poco los intentos
	
	while arboles_colocados < cantidad_arboles and intentos < max_intentos:
		intentos += 1
		
		var px = rng.randi_range(1, ancho - 2)
		var pz = rng.randi_range(1, alto - 2)
		
		# Optimización: get_pixel es lento en bucles grandes, pero aceptable para init.
		# Si quisieras optimizar más, usarías get_data() como en generar_terreno
		var h_pixel = img.get_pixel(px, pz).r
		var altura_real = h_pixel * altura_maxima
		
		if altura_real < altura_minima_vegetacion: continue
		
		var h_derecha = img.get_pixel(px + 1, pz).r * altura_maxima
		var h_abajo = img.get_pixel(px, pz + 1).r * altura_maxima
		var vec_u = Vector3(escala_xz, h_derecha - altura_real, 0)
		var vec_v = Vector3(0, h_abajo - altura_real, escala_xz)
		var normal = vec_v.cross(vec_u).normalized()
		
		if normal.dot(Vector3.UP) < umbral_pendiente_arboles: continue
		
		var pos_x = px * escala_xz - offset_x
		var pos_z = pz * escala_xz - offset_z
		
		var transform = Transform3D()
		transform.origin = Vector3(pos_x, altura_real, pos_z)
		transform = transform.rotated_local(Vector3.UP, rng.randf() * TAU)
		
		var escala_random = rng.randf_range(escala_arbol_min, escala_arbol_max)
		transform = transform.scaled_local(Vector3.ONE * escala_random)
		
		mm.set_instance_transform(arboles_colocados, transform)
		create_collision_for_tree(col_container, transform, escala_random)
		
		arboles_colocados += 1
	
	mm.visible_instance_count = arboles_colocados
	print("Vegetación generada: ", arboles_colocados, " árboles.")

func create_collision_for_tree(padre: Node, transform_arbol: Transform3D, escala: float):
	var sb = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	
	var radio_base = 0.5 
	var altura_tronco = 4.0 
	
	shape.radius = radio_base * escala
	shape.height = altura_tronco * escala
	
	col.shape = shape
	sb.add_child(col)
	sb.transform = transform_arbol
	sb.position += transform_arbol.basis.y * (shape.height / 2.0)
	padre.add_child(sb)

func _bytes_por_formato(formato: int) -> int:
	match formato:
		Image.FORMAT_L8, Image.FORMAT_R8: return 1
		Image.FORMAT_RGB8: return 3
		Image.FORMAT_RGBA8: return 4
		_: return 4
