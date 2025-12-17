extends Node3D

@export_group("Configuración Tiempo")
@export var duracion_dia_minutos : float = 2.0 # Cuánto dura un día entero en la vida real
@export var hora_inicial : float = 12.0 # 0 a 24 horas (12 = mediodía)
@export var pausar_tiempo := false

@export_group("Referencias")
@export var sol : DirectionalLight3D
@export var ambiente : WorldEnvironment

@export_group("Colores")
@export var color_dia : Color = Color("fff8dd") # Blanco cálido
@export var color_atardecer : Color = Color("ff9546") # Naranja fuerte
@export var color_noche : Color = Color("364968") # Azul oscuro/gris

# Variables internas
var tiempo_actual : float = 0.0
var velocidad_tiempo : float = 0.0

func _ready():
	if sol == null:
		# Intentar buscar el sol automáticamente si no se asignó
		if has_node("Sol"): sol = get_node("Sol")
		elif has_node("DirectionalLight3D"): sol = get_node("DirectionalLight3D")
	
	if ambiente == null:
		if has_node("WorldEnvironment"): ambiente = get_node("WorldEnvironment")
		
	# Convertir duración de minutos a velocidad por segundo
	# 24 horas / (minutos * 60 segundos)
	velocidad_tiempo = 24.0 / (duracion_dia_minutos * 60.0)
	tiempo_actual = hora_inicial

func _process(delta):
	if pausar_tiempo: return
	
	# 1. Avanzar el tiempo
	tiempo_actual += delta * velocidad_tiempo
	
	# Si pasamos de las 24h, volvemos a 0
	if tiempo_actual >= 24.0:
		tiempo_actual -= 24.0
		
	actualizar_posicion_sol()
	actualizar_colores(delta)

func actualizar_posicion_sol():
	if sol == null: return
	
	# Mapear 0-24 horas a 0-360 grados (-90 a 270 para que coincida)
	# Mediodía (12h) = -90 grados (Mirando hacia abajo)
	var angulo = (tiempo_actual / 24.0) * 360.0 - 90.0
	
	# Rotamos en X (Subir y bajar)
	sol.rotation_degrees.x = angulo
	# Rotamos un poco en Y para que no salga y se ponga perfectamente recto (más natural)
	sol.rotation_degrees.y = 30.0 

func actualizar_colores(delta):
	if sol == null: return
	
	# LÓGICA DE ILUMINACIÓN SEGÚN LA HORA
	
	# Amanecer (aprox 5am - 7am)
	if tiempo_actual > 5.0 and tiempo_actual < 7.0:
		var peso = (tiempo_actual - 5.0) / 2.0
		sol.light_color = color_noche.lerp(color_atardecer, peso)
		sol.light_energy = peso # Sube la luz
		
	# Mañana (7am - 10am) -> Transición a día
	elif tiempo_actual > 7.0 and tiempo_actual < 10.0:
		var peso = (tiempo_actual - 7.0) / 3.0
		sol.light_color = color_atardecer.lerp(color_dia, peso)
		sol.light_energy = 1.0
		
	# Día (10am - 17pm)
	elif tiempo_actual >= 10.0 and tiempo_actual < 17.0:
		sol.light_color = color_dia
		sol.light_energy = 1.0
		
	# Atardecer (17pm - 19pm)
	elif tiempo_actual >= 17.0 and tiempo_actual < 19.0:
		var peso = (tiempo_actual - 17.0) / 2.0
		sol.light_color = color_dia.lerp(color_atardecer, peso)
		sol.light_energy = 1.0 - (peso * 0.2) # Baja un poco la intensidad
		
	# Anochecer (19pm - 21pm) -> Transición a noche
	elif tiempo_actual >= 19.0 and tiempo_actual < 21.0:
		var peso = (tiempo_actual - 19.0) / 2.0
		sol.light_color = color_atardecer.lerp(color_noche, peso)
		sol.light_energy = 0.8 - (peso * 0.7) # Baja hasta 0.1 de energía
		
	# Noche (21pm - 5am)
	else:
		sol.light_color = color_noche
		sol.light_energy = 0.1 # Luz de luna tenue
		
	# LÓGICA DEL CIELO (WORLD ENVIRONMENT)
	# Si usamos ProceduralSkyMaterial, esto se hace solo con la rotación del sol.
	# Pero si quieres forzar oscuridad total en la noche:
	if ambiente and ambiente.environment and ambiente.environment.sky:
		var mat = ambiente.environment.sky.sky_material
		if mat is ProceduralSkyMaterial:
			# Ajustar el 'sky_energy_multiplier' basado en la energía del sol
			ambiente.environment.sky_rotation.y = delta * 0.01 # Opcional: rotar las nubes lentamente
