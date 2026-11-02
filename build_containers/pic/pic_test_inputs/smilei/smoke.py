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

DiagScalar(every=1)
