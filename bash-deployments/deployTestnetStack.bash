#!/bin/bash

./1-deployTestnetPreLbp.bash $1
./2-deployTestnetLbp.bash $1
./3-deployTestnetPostLbp.bash $1
./4-deployTestnetFinal.bash $1