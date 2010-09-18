#include <QtGui>
#include <QtWebKit>
#include <QProcess>
#include "runtime.h"

Runtime::Runtime(QWidget *window){

  mainWindow = window;
  catalystProcess = 0;

};


void Runtime::openFile( const QString & file = QString()){

  QDesktopServices::openUrl(QUrl::fromLocalFile(file));

}

void Runtime::openUrl( const QString & url = QString()){

  QDesktopServices::openUrl(QUrl(url));

}

void Runtime::openFolder( const QString & folder = QString()){

#ifdef Q_WS_MAC
  QStringList args;
  args << "-e";
  args << "tell application \"Finder\"";
  args << "-e";
  args << "activate";
  args << "-e";
  args << "select POSIX file \""+folder+"\"";
  args << "-e";
  args << "end tell";
  QProcess::startDetached("osascript", args);
#endif
	 
#ifdef Q_WS_WIN
  QStringList args;
  args << "/select," << QDir::toNativeSeparators(filePath);
  QProcess::startDetached("explorer", args);
#endif

}

QString Runtime::getClipboard(){

  QClipboard *clipboard = QApplication::clipboard();
  return(clipboard->text());

}

void Runtime::setClipboard(const QString & text = QString()){

  QClipboard *clipboard = QApplication::clipboard();
  clipboard->setText(text);
}


void Runtime::readyReadCatalyst(){

  QString string(catalystProcess->readAll());

  if (string.contains("powered by Catalyst")){
    emit catalystReady();
  }

  emit catalystRead(string);

}

QString Runtime::getCatalystDir(){

  if (getPlatform() == "osx"){
    QDir path(QCoreApplication::applicationDirPath()+"/../Resources/catalyst/");
    return(path.canonicalPath());
  }

  return("");

}

QString Runtime::getPlatform(){

#ifdef Q_OS_MAC
  return QString("osx");
#endif
 

}

void Runtime::resizeWindow(int w, int h){

  mainWindow->resize(w,h);

}

void Runtime::catalystStateChanged(QProcess::ProcessState newState){

  QString msg;

  if (newState == QProcess::NotRunning){
    emit catalystExit(QString("State changed to 'Not Running'"));
    msg="'Not Running'";
  }

  if (newState == QProcess::Starting) msg ="'Starting'";
  if (newState == QProcess::Running) msg ="'Running'";

  msg.prepend("Catalyst process status changed to ");

  log(msg);

}

void Runtime::catalystError(QProcess::ProcessError error){
  
  QString msg;

  if (error == QProcess::FailedToStart)	msg="Failed to start";
  if (error == QProcess::Crashed)	msg="Killed";
  if (error == QProcess::Timedout)	msg="Timed out";
  if (error == QProcess::WriteError)	msg="Write error";
  if (error == QProcess::ReadError)	msg="Read Error";
  if (error == QProcess::UnknownError)	msg="Unknown Error";

  msg.prepend("Catalyst process: ");

  log(msg);

  emit catalystExit(msg);
  
}

void Runtime::catalystStart(){

  QString program;
  QStringList arguments;

  program = getCatalystDir() + "/" + "/perl5/" + getPlatform() + "/bin/paperperl";

  if (getPlatform() == "osx"){
    arguments << getCatalystDir() + "/script/osx_server.pl" << "--port" << "3210" << "--fork";
  }

  catalystProcess = new QProcess;

  catalystProcess->setReadChannel(QProcess::StandardError);

  catalystProcess->start(program, arguments);

  connect(catalystProcess, SIGNAL(readyRead()), this, SLOT(readyReadCatalyst()));
  
  connect(catalystProcess, SIGNAL(error(QProcess::ProcessError)), this, SLOT(catalystError(QProcess::ProcessError)));
  connect(catalystProcess, SIGNAL(stateChanged(QProcess::ProcessState)), this, SLOT(catalystStateChanged(QProcess::ProcessState)));

}

void Runtime::catalystKill(){

  if (catalystProcess !=0){
    if (catalystProcess->state() == QProcess::Running){
      catalystProcess->close();
    }
  }
}

void Runtime::closeApp(){

  mainWindow->close();

}

QVariantMap Runtime::fileDialog(const QVariantMap & config){


  QString caption;

  if (config.contains("Caption")){
    caption = config["Caption"].toString();
  }
 
  QFileDialog dialog(mainWindow, caption);

  if (config.contains("AcceptMode")){
    if (config["AcceptMode"] == "AcceptOpen") dialog.setAcceptMode(QFileDialog::AcceptOpen);
    if (config["AcceptMode"] == "AcceptSave") dialog.setAcceptMode(QFileDialog::AcceptSave);
  }

  if (config.contains("LookInLabel")) dialog.setLabelText(QFileDialog::LookIn,config["LookInLabel"].toString());
  if (config.contains("FileNameLabel")) dialog.setLabelText(QFileDialog::FileName,config["FileNameLabel"].toString());
  if (config.contains("FileTypeLabel")) dialog.setLabelText(QFileDialog::FileType,config["FileTypeLabel"].toString());
  if (config.contains("AcceptLabel")) dialog.setLabelText(QFileDialog::Accept,config["AcceptLabel"].toString());
  if (config.contains("RejectLabel")) dialog.setLabelText(QFileDialog::Reject,config["RejectLabel"].toString());

  if (config.contains("FileMode")){
  if (config["FileMode"] == "AnyFile") dialog.setFileMode(QFileDialog::AnyFile);
    if (config["FileMode"] == "ExistingFile") dialog.setFileMode(QFileDialog::ExistingFile);
    if (config["FileMode"] == "Directory") dialog.setFileMode(QFileDialog::Directory);
    if (config["FileMode"] == "ExistingFiles") dialog.setFileMode(QFileDialog::ExistingFiles);
  }


  if (config.contains("ShowDirsOnly")) dialog.setOption(QFileDialog::ShowDirsOnly,config["ShowDirsOnly"].toBool());
  if (config.contains("DontResolveSymlinks")) dialog.setOption(QFileDialog::DontResolveSymlinks,config["DontResolveSymlinks"].toBool());
  if (config.contains("DontConfirmOverwrite")) dialog.setOption(QFileDialog::DontConfirmOverwrite,config["DontConfirmOverwrite"].toBool());


  if (config.contains("NameFilters")){
    dialog.setNameFilters(config["NameFilters"].toStringList());
  }

  if (config.contains("DefaultSuffix")){
    dialog.setDefaultSuffix(config["DefaultSuffix"].toString());
  }

  if (config.contains("DefaultSuffix")){
    dialog.setDefaultSuffix(config["DefaultSuffix"].toString());
  }

  if (config.contains("Directory")){
    dialog.setDirectory(config["Directory"].toString());
  }

  QVariantMap output;
  
  if (dialog.exec()){
    output["files"]=dialog.selectedFiles();
    output["answer"]=QString("OK");
  } else {
    output["answer"]=QString("CANCEL");
  }
  
  output["filter"]=dialog.selectedNameFilter();
 
  return(output);
  
}

QVariantMap Runtime::fileInfo(const QString & file){

  QVariantMap map;

  QFileInfo info(file);

  map["exists"] = info.exists();
  map["absoluteDir"] = info.absoluteDir().path(); 
  map["absoluteFilePath"] = info.absoluteFilePath();
  map["absolutePath"] = info.absolutePath(); 
  map["baseName"] = info.baseName(); 
  map["bundleName"] = info.bundleName(); 
  map["canonicalFilePath"] = info.canonicalFilePath(); 
  map["canonicalPath"] = info.canonicalPath(); 
  map["completeBaseName"] = info.completeBaseName(); 
  map["completeSuffix"] = info.completeSuffix(); 
  map["suffix"] = info.suffix(); 
  map["dir"] = info.dir().path(); 
  map["fileName"] = info.fileName(); 
  map["filePath"] = info.filePath(); 
  map["isAbsolute"] = info.isAbsolute(); 
  map["isDir"] = info.isDir(); 
  map["isExecutable"] = info.isExecutable(); 
  map["isFile"] = info.isFile(); 
  map["isHidden"] = info.isHidden(); 
  map["isReadable"] = info.isReadable(); 
  map["isRelative"] = info.isRelative(); 
  map["isRoot"] = info.isRoot(); 
  map["isSymLink"] = info.isSymLink(); 
  map["isWritable"] = info.isWritable(); 

  return map;

}


void Runtime::log(const QString & msg){

  fprintf( stderr, "[%s] %s\n", qPrintable(QDateTime::currentDateTime().toString()), qPrintable(msg) );
}

QVariantMap Runtime::msgBox(const QVariantMap & config){


  QVariantMap output;
  output["dummy"]=QString();
  
  return(output);
  
}

bool Runtime::isDebugMode(){

  return(QCoreApplication::arguments().contains("--debug"));

}


