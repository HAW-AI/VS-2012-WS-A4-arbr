#!/bin/bash

for i in `seq 1 $1`
do
 ('/media/sda7/Studium/VS/Praktikum/A4/datasource/datasource-executable/32bit/DataSource'  14 $i | erl -coockie vsp -sname arbr_coordinator$i -noshell -s coordinator start $2 $i $3 $4) &
done


#('/media/sda7/Studium/VS/Praktikum/A4/datasource/datasource-executable/32bit/DataSource'  14 $i | erl -setcoockie vsp -sname arbr_coordinator$i -noshell -s coordinator start 15010 $i 225.10.1.2 127.0.0.1) &
