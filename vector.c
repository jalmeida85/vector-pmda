/*
 * pcp PMDA used by Vector to launch background tasks.
 *
 * SEE ALSO: http://vectoross.io
 *
 * Copyright 2017 Netflix, Inc.
 * Licensed under the Apache License, Version 2.0 (the "License")
 */

#include <pcp/pmapi.h>
#include <pcp/impl.h>
#include <pcp/pmda.h>
#include "domain.h"

#define WORKING_DIR "/var/log/pcp/vector"
#define VECTOR_DIR "/var/lib/pcp/pmdas/vector"

/*
 * Vector PMDA
 * ===========
 *
 * Task Metrics
 * ------------
 *
 * These are background tasks that are initiated via a store, and then their
 * status can be read via a fetch. Each client can only have one task of
 * each metric in process at a time. For example, multiple clients can have
 * concurrent cpuflamegraph requests, but one client cannot.
 *
 * vector.task.cpuflamegraph
 *	Profile CPU stack traces and create a flame graph.
 * vector.task.disklatencyheatmap
 *	Collect block layer latency using perf and display as a heatmap.
 * vector.task.jstackflamegraph
 *	Process java stacks using jstack and display as a flamegraph.
 * vector.task.pnamecpuflamegraph
 *	Profile CPU instruction pointer and create a package name flame graph.
 * vector.task.uninlinedcpuflamegraph
 *	Profile CPU stack traces with some uninlining for a flame graph.
 * vector.task.pagefaultflamegraph
 *	Trace page faults with stacks and create a flame graph.
 * vector.task.diskioflamegraph
 *	Trace disk I/O issues with stacks and create a flame graph.
 * vector.task.ipcflamegraph
 *	Profile cycles and instructions for an IPC flame graph (needs PMCs).
 * vector.task.cswflamegraph
 *	Profile cycles and instructions for an IPC flame graph (needs PMCs).
 * vector.task.offcpuflamegraph
 *	Trace scheduler events and create an off-CPU time flame graph.
 * vector.task.offwakeflamegraph
 *	Trace scheduler events and create an off-wake time flame graph.
 *
 * The fetch status can be an arbitrary string for the end user to display as
 * task status. Some keywords can be included for interpretation, listed below,
 * the most important is "DONE" to indicate that the task has finished. DONE
 * will only be returned once, and then the task will return to idle ready for
 * the next request. Suggested status strings:
 *
 * "REQUESTED": indicates the request has initiated.
 * "UNKNOWN": status of the client's request was unable to be read.
 * "IDLE": no active request.
 * "DONE[ arg]": request completed. An optional argument may be provided, eg,
 *     showing the output file name.
 * "ERROR[ arg]": an error. An optional message can be provided.
 * "[message]": an arbitrary message to indicate the current status of the
 *     request, provided it does not begin with the previous keywords.
 *
 * A task must finish with either "DONE" or "ERROR" with optional argument.
 */

enum {
	VECTOR_TASK_CPUFLAMEGRAPH = 0,
	VECTOR_TASK_DISKLATENCYHEATMAP,
	VECTOR_TASK_JSTACKFLAMEGRAPH,
	VECTOR_TASK_PNAMECPUFLAMEGRAPH,
	VECTOR_TASK_UNINLINEDCPUFLAMEGRAPH,
	VECTOR_TASK_PAGEFAULTFLAMEGRAPH,
	VECTOR_TASK_DISKIOFLAMEGRAPH,
	VECTOR_TASK_IPCFLAMEGRAPH,
	VECTOR_TASK_CSWFLAMEGRAPH,
	VECTOR_TASK_OFFCPUFLAMEGRAPH,
	VECTOR_TASK_OFFWAKEFLAMEGRAPH,

	VECTOR_TASK_METRIC_COUNT
};

char *tasknames[] = {
	"cpuflamegraph",
	"disklatencyheatmap",
	"jstackflamegraph",
	"pnamecpuflamegraph",
	"uninlinedcpuflamegraph",
	"pagefaultflamegraph",
	"diskioflamegraph",
	"ipcflamegraph",
	"cswflamegraph",
	"offcpuflamegraph",
	"offwakeflamegraph"
};

static pmdaMetric metrictab[] = {
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_CPUFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_DISKLATENCYHEATMAP), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_JSTACKFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_PNAMECPUFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_UNINLINEDCPUFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_PAGEFAULTFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_DISKIOFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_IPCFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_CSWFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_OFFCPUFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
	{ NULL,
		{ PMDA_PMID(0, VECTOR_TASK_OFFWAKEFLAMEGRAPH), PM_TYPE_STRING,
		  PM_INDOM_NULL, PM_SEM_DISCRETE,
		  PMDA_PMUNITS(0, 0, 0, 0, 0, 0) } },
};

static char	*username;
static char	mypath[MAXPATHLEN];
#define CONTAINER_NAME_MAX	256
static char	container_name[CONTAINER_NAME_MAX];
static int	isDSO = 1;		/* == 0 if I am a daemon */

static pmLongOptions longopts[] = {
	PMDA_OPTIONS_HEADER("Options"),
	PMOPT_DEBUG,
	PMDAOPT_DOMAIN,
	PMDAOPT_LOGFILE,
	PMDAOPT_USERNAME,
	PMOPT_HELP,
	PMDA_OPTIONS_END
};

static pmdaOptions opts = {
	.short_options = "D:d:l:U:?",
	.long_options = longopts,
};

/*
 * Return the status string for the given metric, if available.
 * This is stored in a .status file for each context, which is maintained by
 * the background shell program.
 */
char *
getstatus(const char *metric, char *buf, int bufsz, int ctx)
{
	char statuspath[256];
	int fd, sz;
	char *msg = "UNKNOWN";

	sprintf(statuspath, "%s/%s/%s.%d.status", WORKING_DIR, metric, metric, ctx);
	if ((fd = open(statuspath, O_RDONLY)) > 0) {
		if ((sz = read(fd, buf, bufsz)) > 1) {
			msg = buf;
			buf[sz - 1] = '\0';	// nuke the \n
		}
		close(fd);
	}
	return (msg);
}

int
hasstatus(const char *metric, int ctx)
{
	char statuspath[256];
	int fd, has = 0;

	sprintf(statuspath, "%s/%s/%s.%d.status", WORKING_DIR, metric, metric, ctx);
	if ((fd = open(statuspath, O_RDONLY)) > 0) {
		has = 1;
		close(fd);
	}
	return (has);
}

void
rmstatus(const char *metric, int ctx)
{
	char statuspath[256];
	sprintf(statuspath, "%s/%s/%s.%d.status", WORKING_DIR, metric, metric, ctx);
	unlink(statuspath);
}

// input validation, as some is passed to system()
int
badinput(char *str)
{
	char *c = str;
	while (c && *c != '\0') {
		if (*c < '0' || *c > '9')
			return 1;
		c++;
	}
	return 0;
}
	

/*
 * vector_fetchCallBack() schedules tasks.
 */
static int
vector_store(pmResult *result, pmdaExt *pmda)
{
	pmValueSet *vsp = result->vset[0];
	__pmID_int *idp = (__pmID_int *)&vsp->pmid;
	pmAtomValue av;
	static char statusmsg[256];
	char cmd[256];
	char ctxstr[64];
	char *status, *secs, *metricname;
	int ctx;

	if (idp->cluster != 0)
		return PM_ERR_PMID;
	if (vsp->numval != 1)
		return PM_ERR_PMID;

	/*
	 * Set PCP_CONTEXT as a unique ID per user, so that concurrent
	 * users are supported.
	 */
	ctx = pmdaGetContext();
	sprintf(ctxstr, "%d", ctx);
	setenv("PCP_CONTEXT", ctxstr, 1);

	switch (idp->item) {
	case VECTOR_TASK_CPUFLAMEGRAPH:
	case VECTOR_TASK_PNAMECPUFLAMEGRAPH:
	case VECTOR_TASK_UNINLINEDCPUFLAMEGRAPH:
	case VECTOR_TASK_PAGEFAULTFLAMEGRAPH:
	case VECTOR_TASK_DISKIOFLAMEGRAPH:
	case VECTOR_TASK_IPCFLAMEGRAPH:
	case VECTOR_TASK_CSWFLAMEGRAPH:
	case VECTOR_TASK_OFFCPUFLAMEGRAPH:
	case VECTOR_TASK_OFFWAKEFLAMEGRAPH:
		metricname = tasknames[idp->item];

		// fetch optional seconds argument
		secs = "";
		if (pmExtractValue(vsp->valfmt, &vsp->vlist[0],
		    PM_TYPE_STRING, &av, PM_TYPE_STRING) >= 0) {
			secs = av.cp;
			if (badinput(secs))
				return PM_ERR_BADSTORE;
		}

		// if already busy, return try again
		if (hasstatus(metricname, ctx)) {
			status = getstatus(metricname, statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(status, "DONE") != 0 && strstr(status, "ERROR") != status)
				return PM_ERR_AGAIN;
		}

		// application and kernel stacks via perf and flamegraph
		sprintf(cmd, VECTOR_DIR "/%s.sh %s &", metricname, secs);
		if (system(cmd) != 0) {
			fprintf(stderr, "system failed: %s\n",
			    pmErrStr(- oserror()));
		}
		break;

	case VECTOR_TASK_DISKLATENCYHEATMAP:
		// if already busy, return try again
		if (hasstatus("disklatencyheatmap", ctx)) {
			status = getstatus("disklatencyheatmap", statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(status, "DONE") != 0 && strstr(status, "ERROR") != status)
				return PM_ERR_AGAIN;
		}

		// disk I/O latency heat map 
		if (system(VECTOR_DIR "/heatmap.sh &") != 0) {
			fprintf(stderr, "system failed: %s\n",
			    pmErrStr(- oserror()));
		}
		break;

	case VECTOR_TASK_JSTACKFLAMEGRAPH:
		// if already busy, return try again
		if (hasstatus("jstackflamegraph", ctx)) {
			status = getstatus("jstackflamegraph", statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(status, "DONE") != 0 && strstr(status, "ERROR") != status)
				return PM_ERR_AGAIN;
		}

		// java stack flamegraph
		if (system(VECTOR_DIR "/jstack.sh &") != 0) {
			fprintf(stderr, "system failed: %s\n",
			    pmErrStr(- oserror()));
		}
		break;

	default:
		return PM_ERR_PMID;
	}

	return 0;
}

/*
 * vector_fetchCallBack() returns the status of tasks.
 */
static int
vector_fetchCallBack(pmdaMetric *mdesc, unsigned int inst, pmAtomValue *atom)
{
	__pmID_int *idp = (__pmID_int *)&(mdesc->m_desc.pmid);
	static char statusmsg[256];
	char *metricname;
	int ctx;

	if (idp->cluster != 0)
		return PM_ERR_PMID;
	else if (inst != PM_IN_NULL)
		return PM_ERR_INST;

	ctx = pmdaGetContext();

	if (idp->cluster != 0)
		return PM_ERR_PMID;

	switch (idp->item) {
	case VECTOR_TASK_CPUFLAMEGRAPH:
	case VECTOR_TASK_PNAMECPUFLAMEGRAPH:
	case VECTOR_TASK_UNINLINEDCPUFLAMEGRAPH:
	case VECTOR_TASK_PAGEFAULTFLAMEGRAPH:
	case VECTOR_TASK_DISKIOFLAMEGRAPH:
	case VECTOR_TASK_IPCFLAMEGRAPH:
	case VECTOR_TASK_CSWFLAMEGRAPH:
	case VECTOR_TASK_OFFCPUFLAMEGRAPH:
	case VECTOR_TASK_OFFWAKEFLAMEGRAPH:
		metricname = tasknames[idp->item];
		if (hasstatus(metricname, ctx)) {
			atom->cp = getstatus(metricname, statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(atom->cp, "DONE") == 0) {
				sprintf(statusmsg, "DONE %s/%s.%d.svg", metricname, metricname, ctx);
				atom->cp = statusmsg;
				rmstatus(metricname, ctx);
			}
		} else {
			atom->cp = "IDLE";
		}
		break;

	case VECTOR_TASK_DISKLATENCYHEATMAP:
		if (hasstatus("disklatencyheatmap", ctx)) {
			atom->cp = getstatus("disklatencyheatmap", statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(atom->cp, "DONE") == 0)
				rmstatus("disklatencyheatmap", ctx);
		} else {
			atom->cp = "IDLE";
		}
		break;

	case VECTOR_TASK_JSTACKFLAMEGRAPH:
		if (hasstatus("jstackflamegraph", ctx)) {
			atom->cp = getstatus("jstackflamegraph", statusmsg, sizeof (statusmsg), ctx);
			if (strcmp(atom->cp, "DONE") == 0) {
				rmstatus("jstackflamegraph", ctx);
			}
		} else {
			atom->cp = "IDLE";
		}
		break;

	default:
		return PM_ERR_PMID;
	}

	return PMDA_FETCH_STATIC;
}

/*
 * vector_attribute() is used to set the target container.
 */
static int
vector_attribute(int ctx, int attr, const char *value, int len, pmdaExt *pmda)
{
	if (attr == PCP_ATTR_CONTAINER) {
		strncpy(container_name, value, len);
		setenv("PCP_CONTAINER_NAME", container_name, 1);
	}
	return 0;
}

/*
 * Initialise the agent (both daemon and DSO).
 */
void
vector_init(pmdaInterface *dp)
{
	if (isDSO) {
		int sep = __pmPathSeparator();
		snprintf(mypath, sizeof(mypath), "%s%c" "vector" "%c" "help",
		    pmGetConfig("PCP_PMDAS_DIR"), sep, sep);
		pmdaDSO(dp, PMDA_INTERFACE_6, "vector DSO", mypath);
	}
	strcpy(container_name, "");

	if (dp->status != 0)
		return;

	dp->comm.flags |= PDU_FLAG_CONTAINER;
	dp->version.six.attribute = vector_attribute;
	dp->version.six.store = vector_store;
	pmdaSetFetchCallBack(dp, vector_fetchCallBack);
	pmdaInit(dp, NULL, 0,
	    metrictab, sizeof(metrictab) / sizeof(metrictab[0]));
}

/*
 * Set up the agent if running as a daemon.
 */
int main(int argc, char **argv)
{
	int sep = __pmPathSeparator();
	pmdaInterface desc;

	isDSO = 0;
	__pmSetProgname(argv[0]);
	__pmGetUsername(&username);

	snprintf(mypath, sizeof(mypath), "%s%c" "vector" "%c" "help",
	    pmGetConfig("PCP_PMDAS_DIR"), sep, sep);
	pmdaDaemon(&desc, PMDA_INTERFACE_6, pmProgname, VECTOR,
	    "vector.log", mypath);

	pmdaGetOptions(argc, argv, &opts, &desc);
	if (opts.errors) {
		pmdaUsageMessage(&opts);
		exit(1);
	}

	if (opts.username)
		username = opts.username;

	if (system("rm " WORKING_DIR "/*/*.*.status") != 0)
		fprintf(stderr, "removing old status files failed: %s\n",
		    pmErrStr(- oserror()));

	pmdaOpenLog(&desc);
	vector_init(&desc);
	pmdaConnect(&desc);
	pmdaMain(&desc);

	exit(0);
}
