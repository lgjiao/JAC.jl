isdir("bin") || mkdir("bin")
cd("ratip2013-angular-coefficients")
run(`make`)
##x cd("../grasp2013-nucpot")
##x run(`make`)
cd("..")
