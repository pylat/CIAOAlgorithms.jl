struct FINITO_LFinito_batch_iterable{R <: Real, Tx, Tf, Tg}
	f:: Array{Tf}       # smooth term (for now  f_i =f  for all i) 
	g:: Tg         	 	# smooth term (for now  f_i =f  for all i) 
	x0::Tx            	# initial point
	N :: Int64        	# number of data points in the finite sum problem 
	L::Maybe{Array{R}}  # Lipschitz moduli of the gradients
	γ::Maybe{Union{Array{R},R}}  # stepsizes 
	α::R          		# in (0, 1), e.g.: 0.95
	sweeping::Int 		# to only use one stepsize γ
	single_stepsize::Bool 	# to only use one stepsize γ
	batch::Int64 		# batch size
end

mutable struct FINITO_LFinito_batch_state{R <: Real, Tx}  # variables of the iteration, memory place holders for inplace operation, etc
	γ::Array{R}         		# stepsize parameter: can also go to iterable since it is constant throughout 
	hat_γ::R  					# average γ 
	av:: Tx 			 		# the running average
	ind::Array{Array{Int64}}	# running ind set from which the algorithm chooses a coordinate 
	d::Int64 					# number of batches 
	# some extra placeholders 
	z::Tx 						# zbar in the notes  
	∇f_temp::Tx 		 		# temporary placeholder for gradients 
	res::Tx         	 		# residual (to be decided)   # can be removed provided that I find a nicer way to terminate
	z_full::Tx         	 		# residual (to be decided)
	inds::Array{Int64}			# needed for shuffled only  
end

function FINITO_LFinito_batch_state(γ::Array{R}, hat_γ::R, av::Tx, ind, d) where {R, Tx}
	return FINITO_LFinito_batch_state{R, Tx}(γ, hat_γ, av, ind,  d, copy(av), copy(av), copy(av).+R(1), copy(av),  collect(1:d))
end

function Base.iterate(iter::FINITO_LFinito_batch_iterable{R,Tx}) where {R, Tx}  # TODO: separate the case for the linesearch
	N   = iter.N
	r = iter.batch # batch size 
	# create index sets 
	ind = Vector{Vector{Int64}}(undef, 0)
	d =  Int64(floor(N/r))
	for i in 1:d
		push!(ind, collect(r*(i-1)+1:i*r))
	end 
	if r*d < N push!(ind, collect(r*d+1:N)) end 
	# updating the stepsize 
	if iter.γ === nothing 
		if iter.L === nothing 
				@warn "--> smoothness parameter absent"
				return nothing
		else
			γ = zeros(N)  
			for i in 1:N
				iter.single_stepsize ? 
				(γ[i] =iter.α * iter.N / maximum(iter.L)) : (γ[i] =iter.α * iter.N /(iter.L[i]))
			end
		end
	else 
		isa(iter.γ,R) ? (γ = fill(iter.γ,(N,)) ) : (γ = iter.γ) #provided γ
	end 
	#initializing the vectors 
	hat_γ = 1/sum(1 ./ γ)
	av = copy(iter.x0)
	for i in 1:N 	  # for loop to compute the individual nabla f_i for initialization
		∇f, ~ = gradient(iter.f[i], iter.x0) 
		∇f .*=	hat_γ / N  	
		av .-= ∇f
	end
	state = FINITO_LFinito_batch_state(γ, hat_γ, av, ind, cld(N,r))
	return state, state
end

function Base.iterate(iter::FINITO_LFinito_batch_iterable{R,Tx}, state::FINITO_LFinito_batch_state{R, Tx}) where {R, Tx}
	# full update 
	prox!(state.z_full, iter.g, state.av, state.hat_γ)
	state.av .=  state.z_full
	for i in 1:iter.N 
		gradient!(state.∇f_temp, iter.f[i], state.z_full) # update the gradient
		state.av .-= (state.hat_γ/iter.N) .* state.∇f_temp
	end
	if iter.sweeping == 3  # shuffled
		state.inds =  randperm(state.d)
	end
	for j in state.inds 
		prox!(state.z, iter.g, state.av, state.hat_γ)
		for i in state.ind[j] 	
			gradient!(state.∇f_temp, iter.f[i], state.z_full) # update the gradient
			state.av .+=  (state.hat_γ /iter.N) .* state.∇f_temp
			gradient!(state.∇f_temp, iter.f[i], state.z) # update the gradient
			state.av .-=  (state.hat_γ /iter.N) .* state.∇f_temp
			state.av .+=   (state.hat_γ /state.γ[i]) .* (state.z .- state.z_full) 
		end
	end
	return state, state
end 


#TODO list
## fundamental
	#### batch composition is static 
	#### res can be removed, for now I'm using it for testing only 