import math

l0 = 2.0 * math.pi
dx = l0 / 16.0
dt = 0.95 * dx

Main(
    geometry = "1Dcartesian",
    interpolation_order = 2,
    cell_length = [dx],
    grid_length = [16.0 * dx],
    number_of_patches = [2],
    timestep = dt,
    simulation_time = 2.0 * dt,
    EM_boundary_conditions = [["silver-muller"]],
    print_every = 1,
)

Species(
    name = "e_spin",
    position_initialization = "regular",
    momentum_initialization = "cold",
    particles_per_cell = 1,
    mass = 1.0,
    charge = -1.0,
    number_density = 1.0e-6,
    boundary_conditions = [["remove", "remove"]],
    spin_initialization = "profile",
    polarization = [0.0, 0.0, 1.0],
)

DiagScalar(every=1)
