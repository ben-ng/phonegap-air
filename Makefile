all:
	echo "Pick something to actually do" && exit 1

reset: clean
	phonegap create ota-app com.foo.bar OTAApplication && cd ota-app && phonegap build ios

clean:
	rm -Rf ota-app
