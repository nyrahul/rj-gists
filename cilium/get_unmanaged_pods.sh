#!/bin/bash

ALLPOD=/tmp/fill-info1.$$.txt
NOCILIUMPOD=/tmp/fill-info2.$$.txt
CILIUMPOD=/tmp/fill-info3.$$.txt
UNMGDPODS=/tmp/fill-info4.$$.txt
CILIUM_NS="kube-system"
trap "cleanup" EXIT

cleanup()
{
	rm -f /tmp/fill-info*.txt
	echo bye
}

main()
{
	echo "fetching node info..."
	kubectl get pod -o=custom-columns=NODE:.spec.nodeName,NAME:.metadata.name,NAMESPACE:.metadata.namespace,IP:.status.podIP,HOSTNETWORK:.spec.hostNetwork,PHASE:.status.phase --all-namespaces --no-headers > $ALLPOD #get all pods with NODE,POD,NAMESPACE,IP details
	grep -v "cilium-.* .*$CILIUM_NS" $ALLPOD > $NOCILIUMPOD #remove cilium-agent lines
	grep "cilium-..... .*$CILIUM_NS" $ALLPOD > $CILIUMPOD	#get cilium-agent lines
	while read cil; do
		node=`echo "$cil" | awk '{print $1}'`
		cilpod=`echo "$cil" | awk '{print $2}'`
		# get list of IP addresses from cilium-endpoint-list
		echo "fetching endpoint info from [$CILIUM_NS $cilpod] on node:$node..."
		iplist=`kubectl exec -q -n $CILIUM_NS $cilpod -- cilium endpoint list -o json | jq ".[].status.networking.addressing[0].ipv4" -r | sort | tr "\n" "|"`
		iplist=${iplist/|null|/}
		grep "$node" $NOCILIUMPOD | egrep -v "$iplist" | grep '<none>' > $UNMGDPODS
		[[ ! -s $UNMGDPODS ]] && continue
		echo "---= UNMANAGED PODS on node:[$node] [$cilpod] =---"
		while read line; do
			pod=`echo $line | awk '{print $2'}`
			kubectl get pod -A | grep "$pod"
		done < $UNMGDPODS
	done < $CILIUMPOD
}

main
