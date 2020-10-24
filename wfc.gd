extends TileMap

const UP = Vector2(0, -1)
const LEFT = Vector2(-1, 0)
const DOWN = Vector2(0, 1)
const RIGHT = Vector2(1, 0)
const DIRS = [UP, DOWN, LEFT, RIGHT]

var input_matrix: Array = [
	['L','L','L','L'],
	['L','L','L','L'],
	['L','L','L','L'],
	['L','C','C','L'],
	['C','S','S','C'],
	['S','S','S','S'],
	['S','S','S','S'],
]

var input_matrix2: Array = [
	['L','L','C','L','L','L','L','L'],
	['L','C','S','C','L','L','L','L'],
	['C','S','S','S','C','L','L','L'],
	['L','C','S','S','S','C','L','L'],
	['C','S','S','S','S','S','C','L'],
	['L','C','S','S','C','C','L','L'],
	['C','S','S','C','L','L','L','L'],
	['L','C','C','L','L','L','L','L'],
	['L','L','L','L','L','L','L','L'],
]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var comp_weights = Helper.parse_example_matrix(input_matrix)
		var compatibility_oracle = CompatibilityOracle.new(comp_weights[0])
		var model = Model.new([20, 20], comp_weights[1], compatibility_oracle)
		var output = model.run()
		
		var y = 0
		var x = 0
		for row in output:
			for tile in row:
				var code
				match(tile):
					'L':
						code = 2
					'S':
						code = 1
					'C':
						code = 0
	
				set_cell(x, y, code)
				x += 1
			x = 0
			y += 1

func _ready() -> void:
	randomize()
	
class Helper:
	static func sum_arr(arr: Array) -> float:
		var res: float = 0.0
		for e in arr:
			res += e
			
		return res
	
	static func array_to_set(arr: Array) -> Array:
		var set = []
		for e in arr:
			if not e in set:
				set.append(e)
				
		return set
	
	# checks which neighbors are possible for this tile
	# returns the possible directions
	static func valid_dirs(coord: Vector2, mat_dim: Array) -> Array:
		var dirs: Array = []
		if coord.x > 0: dirs.append(LEFT)
		if coord.x < mat_dim[1] - 1: dirs.append(RIGHT)
		if coord.y > 0: dirs.append(UP)
		if coord.y < mat_dim[0] - 1: dirs.append(DOWN)
	
		return dirs
	
	# Parses an example matrix and extracts tile compatiblities and tile weights
	static func parse_example_matrix(mat: Array) -> Array:
		var compatibilities: Array = []
		var weights: Dictionary = {}
		var mat_dim: Array = [len(mat), len(mat[0])]
	
		# loop over the matrix and count the number of each individual tile
		for y in range(mat_dim[0]):
			for x in range(mat_dim[1]):
				var cur_tile = mat[y][x]
				if not mat[y][x] in weights:
					weights[cur_tile] = 0
				weights[cur_tile] += 1
	
				# for the current tile get all possible neighbor directions
				var dirs: Array = Helper.valid_dirs(Vector2(x, y), mat_dim)
				
				# for each direction get the neighbor tiles
				for d in dirs:
					var other_tile = mat[y + d[1]][x + d[0]]
					var comp: Array = [cur_tile, other_tile, d]
					if not comp in compatibilities:
						compatibilities.append(comp)
		
		return [compatibilities, weights]

class CompatibilityOracle:
	var data: Array
	
	func _init(_data: Array) -> void:
		self.data = _data
		
	func check(tile1, tile2, dir: Vector2) -> bool:
		return self.data.has([tile1, tile2, dir])

class Wavefunction:
	var coefficients: Array
	var weights: Dictionary
	
	static func mk(_size: Array, _weights: Dictionary) -> Wavefunction:
		var coeff = Wavefunction.init_coefficients(_size, _weights.keys().duplicate())
		return Wavefunction.new(coeff, _weights)
	
	static func init_coefficients(size: Array, tiles: Array) -> Array:
		var coeff = []
		
		for _i in range(size[0]):
			var row = []
			for _j in range(size[1]):
				row.append(tiles.duplicate())
			coeff.append(row.duplicate())
		
		return coeff
	
	func _init(_coefficients: Array, _weights: Dictionary) -> void:
		self.coefficients = _coefficients
		self.weights = _weights
	
	func get_tiles(coords: Vector2):
		return self.coefficients[coords.y][coords.x]
		
	func get_collapsed(coords: Vector2): 
		var opts = self.get_tiles(coords)
		assert(len(opts) == 1)
		return opts[0]
		
	func get_all_collapsed():
		var collapsed: Array = []
		for y in len(self.coefficients):
			var row: Array = []
			for x in len(self.coefficients[0]):
				row.append(self.get_collapsed(Vector2(x,y)))
			collapsed.append(row)
		
		return collapsed

	func shannon_entropy(coords: Vector2):
		var sum_of_weights: float = 0
		var sum_of_weight_log_weights: float = 0
		for opt in self.get_tiles(coords):
			var weight = self.weights[opt]
			sum_of_weights += weight
			sum_of_weight_log_weights += weight * log(weight)
	
		return log(sum_of_weights) - (sum_of_weight_log_weights / sum_of_weights)
	
	func is_fully_collapsed() -> bool:
		for y in len(self.coefficients):
			for x in len(self.coefficients[y]):
				if len(self.coefficients[y][x]) > 1:
					return false
		
		return true
	
	func collapse(coords: Vector2) -> void:
		var opts = self.get_tiles(coords)
		var valid_weights: Dictionary = Dictionary()
		var tiles: Array = self.weights.keys().duplicate()
		for tile in tiles:
			if tile in opts:
				valid_weights[tile] = self.weights[tile]
		
		var total_weights = Helper.sum_arr(valid_weights.values())
		var rnd = randf() * total_weights
		
		var chosen = null
		
		for tile in valid_weights:
			rnd -= valid_weights[tile]
			if rnd < 0:
				chosen = tile
				break
		
		self.coefficients[coords.y][coords.x] = [chosen].duplicate()
		
	func constrain(coords: Vector2, forbidden_tile) -> void:
		self.coefficients[coords.y][coords.x].erase(forbidden_tile)

# responsible for orchestrating the wavefunction collapse algorithm
class Model:
	var output_size: Array
	var compatibility_oracle: CompatibilityOracle
	var wfn: Wavefunction
	
	func _init(_out_size: Array, _weights: Dictionary, _compatibility_oracle: CompatibilityOracle) -> void:
		self.output_size = _out_size
		self.compatibility_oracle = _compatibility_oracle
		self.wfn = Wavefunction.mk(_out_size, _weights)
	
	# collapses the wavefunction until fully collapsed, then returns 2-D matrix
	# of the final collapsed state
	func run():
		while not self.wfn.is_fully_collapsed():
			self._iterate()
			
		return self.wfn.get_all_collapsed()
	
	# performs a single iteration of the wavefunction collapse algorithm
	func _iterate() -> void:
		# 1. find coordinates of minimum entropy
		var coords: Vector2 = self._min_entropy_coords()
		# 2. collapse wavefunction at these coords
		self.wfn.collapse(coords)
		# 3. propagate consequences of the collapse
		self._propagate(coords)
	
	# propagates the consequences of the wavefunction at coords collapsing until
	# no consequences remain
	func _propagate(coords: Vector2) -> void:
		var stack: Array = [coords]
		
		while len(stack) > 0:
			var cur_coords = stack.pop_back()
			# get a list of all possible tiles at current location
			var cur_possible_tiles = self.wfn.get_tiles(cur_coords)
			# iterate through all neighbor coords
			var neighbor_dirs: Array = Helper.valid_dirs(cur_coords, self.output_size)
			for dir in neighbor_dirs:
				var neighbor_coords: Vector2 = Vector2(cur_coords[0] + dir[0], cur_coords[1] + dir[1])
				
				var arr = self.wfn.get_tiles(neighbor_coords)
				var neighbor_tiles = Helper.array_to_set(arr)
				assert(arr == neighbor_tiles)
				# iterate through each possible tile of the neighbor cur_coords
				for neighbor_tile in neighbor_tiles:
					# check wether the tile is compatible with any tile in the current
					# location's wavefunction
					var other_tile_possible = false
					for cur_tile in cur_possible_tiles:
						if self.compatibility_oracle.check(cur_tile, neighbor_tile, dir):
							other_tile_possible = true
							break
					
					# If the tile is not compatible with any of the tiles in
					# the current location's wavefunction then it is impossible
					# for it to ever get chosen. We therefore remove it from
					# the other location's wavefunction.
					if not other_tile_possible:
						self.wfn.constrain(neighbor_coords, neighbor_tile)
						stack.append(neighbor_coords)
		
	# returns coords of the location whose wavefunction has the lowest entropy
	func _min_entropy_coords():
		var min_entropy = null
		var min_entropy_coords = null
		
		for y in range(self.output_size[0]):
			for x in range(self.output_size[1]):
				var coords: Vector2 = Vector2(x, y)
				if len(self.wfn.get_tiles(coords)) == 1:
					continue
				
				# calculate the entropy for these coordinates and add minimal noise
				var entropy: float = self.wfn.shannon_entropy(coords)
				var entropy_with_noise: float = entropy - (randf() / 1000)
				
				# if entropy is the smallest save the coords
				if min_entropy == null or entropy_with_noise < min_entropy:
					min_entropy = entropy_with_noise
					min_entropy_coords = coords
		
		return min_entropy_coords
