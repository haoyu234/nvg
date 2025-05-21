#! /bin/bash

nim -d:debug -d:danger --cc:gcc --passC:-g c tests/tgl.nim
