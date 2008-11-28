module Yi.IReader where

import Control.Monad.State
import Data.List
import System.Directory (getHomeDirectory)

import Yi.Keymap
import Yi.Prelude
import Yi.Buffer.Misc
import Yi.Buffer.Region
import Yi.Buffer.Normal
import Yi.Buffer.HighLevel
import qualified System.IO as IO


type Article = String
type ArticleDB = [String]

-- | Get the first article in the list. We use the list to express relative priority;
-- the first is the most, the last least. We then just cycle through - everybody gets equal time.
getLatestArticle :: ArticleDB -> Article
getLatestArticle [] = ""
getLatestArticle adb = head adb

-- | We remove the old first article, and we stick it on the end of the
-- list using the presumably modified version.
updateSetLast :: ArticleDB -> Article -> ArticleDB
updateSetLast [] a = [a]
updateSetLast (_:bs) a = bs ++ [a]

-- | Insert a new article with top priority.
insertArticle :: ArticleDB -> Article -> ArticleDB
insertArticle adb a = a:adb

-- | Delete the first
deleteArticle :: ArticleDB -> Article -> ArticleDB
deleteArticle = flip delete

writeDB :: ArticleDB -> YiM ()
writeDB adb = io $ join $ liftM (flip writeFile $ show adb) $ dbLocation

readDB :: YiM ArticleDB
readDB = io $ rddb `catch` (\_ -> return (return []))
         where rddb = do db <- liftM readfile $ dbLocation
                         liftM read db
               -- We need these for strict IO
               readfile :: FilePath -> IO String
               readfile f =  IO.openFile f IO.ReadMode >>= hGetContents
               hGetContents :: IO.Handle -> IO.IO String
               hGetContents h  = IO.hGetContents h >>= \s -> length s `seq` return s

dbLocation :: IO FilePath
dbLocation = getHomeDirectory >>= \home -> return (home ++ "/.yi/articles.db")

-- | Returns the database as it exists on the disk, and the current Yi buffer contents.
oldDbNewArticle :: YiM (ArticleDB, Article)
oldDbNewArticle = do olddb <- readDB
                     newarticle <- withBuffer getBufferContents
                     return (olddb, newarticle)

getBufferContents :: BufferM String
getBufferContents = join $ liftM readRegionB $ regionOfB Document

-- | Given an 'ArticleDB', dump the scheduled article into the buffer (replacing previous contents).
setDisplayedArticle :: ArticleDB -> YiM ()
setDisplayedArticle newdb = do let nextarticle = getLatestArticle newdb
                               withBuffer (replaceBufferContent nextarticle)
                               withBuffer topB -- replaceBufferContents moves us
                                               -- to bottom?

-- | Delete current article (the article as in the database), and go to next one.
nextArticle :: YiM ()
nextArticle = do ((_:ndb),_) <- oldDbNewArticle -- throw away changes, drop head
                 setDisplayedArticle ndb
                 writeDB ndb

-- | The main action. We fetch the old database, we fetch the modified article from the buffer,
-- then we call the function 'updateSetLast' which removes the first article and pushes our modified article
-- to the end of the list.
saveAndNextArticle :: YiM ()
saveAndNextArticle = do (oldb,newa) <- oldDbNewArticle
                        let newdb = updateSetLast oldb newa
                        setDisplayedArticle newdb
                        writeDB newdb

-- | Assume the buffer is an entirely new article just imported this second, and save it.
-- We don't want to use 'updateSetLast' since that will erase an article.
saveAsNewArticle :: YiM ()
saveAsNewArticle = do (oldb,newa) <- oldDbNewArticle
                      let newdb = insertArticle oldb newa
                      writeDB newdb