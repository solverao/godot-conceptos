extends MeshInstance3D

@export_group("Agua")
@export var generar_agua := true
@export var nivel_agua := 2.0  # Debería ser similar a tu altura_transicion del terreno
@export var material_agua : Material

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
